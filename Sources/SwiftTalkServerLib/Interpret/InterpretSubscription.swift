//
//  InterpretSubscription.swift
//  Bits
//
//  Created by Chris Eidhof on 13.12.18.
//

import Foundation

extension Route.Subscription {
    func interpret<I: Interp>() throws -> I {
        return I.requireSession { sess in
            try self.interpret2(sesssion: sess)
        }
    }

    private func interpret2<I: Interp>(sesssion sess: Session) throws -> I {
        let user = sess.user
        func newSubscription(couponCode: String?, team: Bool, errs: [String]) throws -> I {
            if let c = couponCode {
                return I.onSuccess(promise: recurly.coupon(code: c).promise, do: { coupon in
                    return try I.write(newSub(coupon: coupon, team: team, errs: errs))
                })
            } else {
                return try I.write(newSub(coupon: nil, team: team, errs: errs))
            }
        }
        
        switch self {
        case let .create(couponCode, team):
            return I.verifiedPost { dict in
                guard let planId = dict["plan_id"], let token = dict["billing_info[token]"] else {
                    throw ServerError(privateMessage: "Incorrect post data", publicMessage: "Something went wrong")
                }
                let plan = try Plan.all.first(where: { $0.plan_code == planId }) ?! ServerError.init(privateMessage: "Illegal plan: \(planId)", publicMessage: "Couldn't find the plan you selected.")
                let cr = CreateSubscription.init(plan_code: plan.plan_code, currency: "USD", coupon_code: couponCode, starts_at: nil, account: .init(account_code: user.id, email: user.data.email, billing_info: .init(token_id: token)))
                return I.onSuccess(promise: recurly.createSubscription(cr).promise, message: "Something went wrong, please try again", do: { sub_ in
                    switch sub_ {
                    case .errors(let messages):
                        log(RecurlyErrors(messages))
                        if messages.contains(where: { $0.field == "subscription.account.email" && $0.symbol == "invalid_email" }) {
                            let response = registerForm(couponCode: couponCode, team: team).render(.init(user.data), [ValidationError("email", "Please provide a valid email address and try again.")])
                            return I.write(response)
                        }
                        return try newSubscription(couponCode: couponCode, team: team, errs: messages.map { $0.message })
                    case .success(let sub):
                        return I.query(user.changeSubscriptionStatus(sub.state == .active)) {
                            I.redirect(to: team ? .account(.teamMembers) : .account(.thankYou))
                        }
                    }
                })
            }
        case let .new(couponCode, team):
            if !user.data.confirmedNameAndEmail {
                let resp = registerForm(couponCode: couponCode, team: team).render(.init(user.data), [])
                return I.write(resp)
            } else {
                return I.query(Task.unfinishedSubscriptionReminder(userId: user.id).schedule(weeks: 1)) {
                    var u = user
                    u.data.role = team ? .teamManager : .user
                    return I.query(u.update()) {
                        try newSubscription(couponCode: couponCode, team: team, errs: [])
                    }
                }
            }
        case let .teamMember(token, terminate):
            return I.query(Row<UserData>.select(teamToken: token)) { row in
                guard let teamManager = row else {
                    throw ServerError(privateMessage: "signup token doesn't exist: \(token)", publicMessage: "This signup link is invalid. Please get in touch with your team manager for a new one.")
                }
                
                func registerTeamMember() -> I {
                    let teamMemberData = TeamMemberData(userId: teamManager.id, teamMemberId: user.id)
                    return I.query(teamMemberData.insert) { _ in
                        return I.execute(Task.syncTeamMembersWithRecurly(userId: teamManager.id).schedule(minutes: 5)) { _ in
                            if !user.data.confirmedNameAndEmail {
                                let resp = registerForm(couponCode: nil, team: false).render(.init(user.data), [])
                                return I.write(resp)
                            } else {
                                return I.redirect(to: .home)
                            }
                        }
                    }
                }
                
                if sess.selfPremiumAccess == true {
                    if terminate {
                        return I.onSuccess(promise: user.currentSubscription.promise.map(flatten)) { sub in
                            return I.onSuccess(promise: recurly.terminate(sub, refund: .partial).promise) { result in
                                switch result {
                                case .success: return registerTeamMember()
                                case .errors(let errs): throw RecurlyErrors(errs)
                                }
                            }
                        }
                    } else {
                        return I.write(teamMemberSubscribeForSelfSubscribed(signupToken: token))
                    }
                } else {
                    return registerTeamMember()
                }
            }
        case .cancel:
            return I.verifiedPost { _ in
                return I.onSuccess(promise: user.currentSubscription.promise.map(flatten)) { sub in
                    guard sub.state == .active else {
                        throw ServerError(privateMessage: "cancel: no active sub \(user) \(sub)", publicMessage: "Can't find an active subscription.")
                    }
                    return I.onSuccess(promise: recurly.cancel(sub).promise) { result in
                        switch result {
                        case .success: return I.redirect(to: .account(.billing))
                        case .errors(let errs): throw RecurlyErrors(errs)
                        }
                    }
                    
                }
            }
        case .upgrade:
            return I.verifiedPost { _ in
                return I.onSuccess(promise: sess.user.currentSubscription.promise.map(flatten), do: { sub throws -> I in
                    guard let u = sub.upgrade(vatExempt: false) else { throw ServerError(privateMessage: "no upgrade available \(sub)", publicMessage: "There's no upgrade available.")}
                    return I.query(sess.user.teamMembers) { teamMembers in
                        I.onSuccess(promise: recurly.updateSubscription(sub, plan_code: u.plan.plan_code, numberOfTeamMembers: teamMembers.count).promise, do: { result throws -> I in
                            I.redirect(to: .account(.billing))
                        })
                    }
                })
            }
        case .reactivate:
            return I.verifiedPost { _ in
                return I.onSuccess(promise: user.currentSubscription.promise.map(flatten)) { sub in
                    guard sub.state == .canceled else {
                        throw ServerError(privateMessage: "cancel: no active sub \(user) \(sub)", publicMessage: "Can't find a cancelled subscription.")
                    }
                    return I.onSuccess(promise: recurly.reactivate(sub).promise) { result in
                        switch result {
                        case .success: return I.redirect(to: .account(.thankYou))
                        case .errors(let errs): throw RecurlyErrors(errs)
                        }
                    }
                    
                }
            }
        }
    }
}

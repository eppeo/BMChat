//
//  UserManager.swift
//  ZebraKing
//
//  Created by 武飞跃 on 2017/9/11.
//  Copyright © 2017年 武飞跃. All rights reserved.
//
import Foundation
import ImSDK
import IMMessageExt

//MARK: - 会话中心管理
open class CentralManager: NSObject {
    
    public private(set) var conversationList = Set<Conversation>()
    
    // 监听消息通知
    private var onResponseNotification = Set<ListenterMessages>()
    
    //当前聊天的对象
    private var chattingConversation: Conversation?
    
    /// 主动触发聊天
    ///
    /// - Parameters:
    ///   - type: 聊天类型  单人或群组
    ///   - id: 房间号
    /// - Returns: 会话对象
    public func holdChat(with type: TIMConversationType, id: String) -> Conversation? {
        let wrappedConversation = conversation(with: type, id: id)
        chattingConversation = wrappedConversation
        return chattingConversation
    }
    
    
    /// 主动释放聊天
    public func waiveChat() {
        chattingConversation?.free()
        chattingConversation = nil
    }
    
    /// 从集合中获取指定会话(如果集合中不存在,才会创建一个)
    ///
    /// - Parameters:
    ///   - type: 会话类型  c2c 群消息 系统消息
    ///   - id: 会话id
    /// - Returns: 返回一个会话任务
    private func conversation(with type: TIMConversationType, id: String) -> Conversation? {
        
        if let targetConversation = conversationList.first(where: { $0.receiverId == id && $0.type == type }) {
            return targetConversation
        }
        
        if let targetConversation = Conversation(type: type, id: id) {
            conversationList.insert(targetConversation)
            return targetConversation
        }
        
        return nil
    }
    
    private func removeListenter(type: ListenterMessages.TypeFlag) {
        guard var listenerMessages = onResponseNotification.first(where: { $0.flag == type }) else {
            return
        }
        listenerMessages.completion = nil
        onResponseNotification.remove(listenerMessages)
    }
    
    /// 删除本地会话窗口
    public func deleteConversation(with type: TIMConversationType, id: String) {
        TIMManager.sharedInstance()?.deleteConversationAndMessages(type, receiver: id)
    }
}

//MARK: - 未读消息
extension CentralManager {
    
    /// 监听消息通知
    public func listenterMessages(completion: @escaping ListenterMessages.NotificationCompletion) {
        TIMManager.sharedInstance().add(self)
        onResponseNotification.insert(ListenterMessages(flag: .outsideNotification, completion: completion))
    }
    
    public func removeListenerMessage() {
        TIMManager.sharedInstance()?.remove(self)
        removeListenter(type: .outsideNotification)
    }
    
    //根据会话类型监听此会话的未读消息数
    public func listenerUnReadCount(with type: TIMConversationType, id: String, completion:@escaping CountCompletion) {
        
        let wrappedConversation = conversation(with: type, id: id)
        let unreadCount = wrappedConversation?.unreadMessageCount ?? 0
        
        let onresponseNotification: ListenterMessages.NotificationCompletion = { ( _, _ )in
            completion(unreadCount)
        }
        
        onResponseNotification.insert(ListenterMessages(flag: .unreadMessage, completion: onresponseNotification))
    }
    
    public func removeListenerUnReadCount() {
        removeListenter(type: .unreadMessage)
    }
}

extension CentralManager: TIMMessageListener {
    
    public func onNewMessage(_ msgs: [Any]!) {
        
        for anyObjcet in msgs {
            
            print("有消息进来")
            
            guard let message = anyObjcet as? TIMMessage,
                let timConversation = message.getConversation() else { return }
            
            let conversation = Conversation(conversation: timConversation)
            
            //此会话是否存在聊天列表中
            if let didExistingConversation = conversationList.first(where: { $0 == conversation }) {
                
                didExistingConversation.onReceiveMessageCompletion?(message)
                
                //正处于当前活跃的会话页面时,将消息设置为已读
                if didExistingConversation == chattingConversation {
                    chattingConversation?.alreadyRead(message: message)
                    return
                }
                
                if message.isSelf() == false {
                    //列表中,别的会话发过来的消息, 就给个通知
                    handlerNotification(with: conversation)
                }
                
            }
            else {
                //新的会话不在列表中,可能是对方先发起的聊天,需要插入到会话列表中
                conversationList.insert(conversation)
                handlerNotification(with: conversation)
            }
            
        }
    }
    
    private func handlerNotification(with conversation: Conversation) {
        let content = conversation.getLastMessage
        onResponseNotification.forEach{ $0.completion?(conversation.conversation.getReceiver(), content) }
    }

}

public struct ListenterMessages {
    
    public typealias NotificationCompletion = (_ receiverID: String, _ content: String?) -> Void
    
    public enum TypeFlag: String {
        
        //未读消息
        case unreadMessage
        
        //外部通知
        case outsideNotification
    }
    
    let flag: TypeFlag
    var completion: NotificationCompletion?
    
    init(flag: TypeFlag, completion: @escaping NotificationCompletion) {
        self.flag = flag
        self.completion = completion
    }
    
}

extension ListenterMessages: Hashable {
    
    public var hashValue: Int {
        return flag.hashValue
    }
    
    public static func == (lhs: ListenterMessages, rhs: ListenterMessages) -> Bool {
        return lhs.flag == rhs.flag
    }
}

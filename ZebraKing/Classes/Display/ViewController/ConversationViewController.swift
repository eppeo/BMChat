//
//  ConversationViewController.swift
//  Alamofire
//
//  Created by 武飞跃 on 2018/1/24.
//

import UIKit

open class ConversationViewController: MessagesViewController, MessageCellDelegate, ChatAudioRecordDelegate {

    public let task: Task
    
    public init(task: Task) {
        self.task = task
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()

        scrollsToBottomOnKeybordBeginsEditing = true
        maintainPositionOnKeyboardFrameChanged = true
        
        messagesCollection.messageDataSource = self
        messagesCollection.messagesLayoutDelegate = self
        messagesCollection.messagesDisplayDelegate = self
        messagesCollection.messageCellDelegate = self
        messagesCollection.setIndicatorHeader {
            //下拉加载更多消息
            self.loadMoreMessages()
        }
        
        //监听新消息过来
        task.listenerNewMessage(completion: { [unowned self](receiveMsg) in
            self.messagesCollection.reloadDataAndKeepOffset()
        })
        
        //已读回执,刷新tableView
        task.listenerUpdateReceiptMessages { [unowned self] in
            //因为可能好几条消息都未读, 这里只刷新一个item还不行, 要reloadData
            self.messagesCollection.reloadData()
        }
        
        loadMoreMessages()
    }
    
    private func loadMoreMessages() {
        
        //FIXME: - loadRecentMessages要在viewController销毁时, 置为nil, 否则会因为逃逸闭包, unowned修饰引起崩溃
        task.loadRecentMessages { [weak self] (result, isFirstLoadData) in
           
            guard let this = self else { return }
            
            switch result {
            case .success(let receiveMsg):
            
                guard receiveMsg.isEmpty == false else {
                    this.messagesCollection.endRefreshingAndNoMoreData()
                    return
                }
                
                if isFirstLoadData {
                    this.messagesCollection.reloadDataAndMoveToBottom()
                }
                else {
                    
                    //下拉加载资源时, 会导致selectedIndex索引位置改变, 需要手动更新一下
                    this.selectedIndexPath?.section += receiveMsg.count
                    
                    //1.刷新TableView
                    this.messagesCollection.reloadDataAndKeepOffset()
                    
                    //2.收起菊花, 如果没有更多数据, 就隐藏indicator
                    if receiveMsg.count <= this.task.loadMessageCount {
                        this.messagesCollection.endRefreshingAndNoMoreData()
                    }
                    else {
                        this.messagesCollection.endRefreshing()
                    }
                }
                
            case .failure:
                this.showToast(message: "数据拉取失败, 请退出重试")
                this.messagesCollection.endRefreshing()
            }
        
        }
        
    }
    
    //FIXME: - 后期要后话, conversation自己控制生命周期
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        task.free()
    }

    final override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        //避免消息过多，内存激增。
        task.removeSubrange()
        messagesCollection.reloadData()
    }
    
    public func didTapMessage(in cell: MessageCollectionViewCell, message: MessageType) { }
    
    public func didContainer(in cell: MessageCollectionViewCell, message: MessageType) { }
    
    func showToast(message: String) {
        fatalError("子类必须实现")
    }
}

extension ConversationViewController: MessagesDataSource {
    
    public func isFromCurrentSender(message: MessageType) -> Bool {
        
        /*
         消息显示规则是: 先渲染到界面中, 然后在根据发送状态, 做后续处理, 如果发送未成功就将之前渲染的移除掉, 因为是先渲染的, 就会造成消息体自身sender对象为空, 所以这里判断为空, 表示由自己发出去的
         */
        
        if message.sender.id.isEmpty {
            return true
        }
        
        return currentSender() == message.sender
    }
    
    
    public func currentSender() -> Sender {
        return task.host
    }
    
    public func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return task.messagesList[indexPath.section]
    }
    
    public func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
        return task.messagesList.count
    }
    
    
    
}

extension ConversationViewController: MessagesLayoutDelegate {
    
    public func avatarSize(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGSize {
        return CGSize(width: 42, height: 42)
    }
    
    public func messagePadding(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIEdgeInsets {
        return UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
    }
    
    public func messageInsets(at indexPath: IndexPath, message: MessageType, in messagesCollectionView: MessagesCollectionView) -> UIEdgeInsets {
        if isFromCurrentSender(message: message) {
            return UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 14)
        }
        else {
            return UIEdgeInsets(top: 11, left: 14, bottom: 11, right: 12)
        }
    }
}

extension ConversationViewController: MessagesDisplayDelegate {
    
    public func readStatus(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> Bool {
        return true
    }
    
    public func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
        return [.url, .address, .phoneNumber, .date]
    }
    
    public func detectorAttributes(for detector: DetectorType, and message: MessageType, at indexPath: IndexPath) -> [NSAttributedStringKey : Any] {
        return MessageLabel.defaultAttributes
    }
}

extension ConversationViewController {
    
    func onMessageCancelSend() {
        guard task.messagesList.isEmpty == false else { return }
        
        task.removeLast()
        //FIXME: - 不用刷新是否可行
        messagesCollection.deleteSections(task.messagesList.indexSet)

        if task.messagesList.isEmpty == false {
            messagesCollection.reloadDataAndKeepOffset()
        }
    }
    
    //已测试
    public func onMessageWillSend(_ message: MessageElem) {
        task.append(message)
        messagesCollection.insertSections(task.messagesList.indexSet)
        messagesCollection.scrollToBottom()
        messageInputBar.inputTextView.text = String()
    }
    
    public func replaceLastMessage(newMsg: MessageElem) {
        task.replaceLast(newMsg)
        messagesCollection.performBatchUpdates(nil)
        if task.messagesList.count >= 1 {
            messagesCollection.reloadDataAndKeepOffset()
        }
    }
    
    /// 发送消息
    ///
    /// - Parameter msg:
    public func sendMsg(msg: MessageElem) {
        
        //发送消息
        task.send(message: msg) { [weak self](result) in
            //FIXME: - code 值不对
            if case .failure(let error) = result, error == .unsafe {
                self?.showToast(message: "请不要发送敏感词汇")
                self?.onMessageCancelSend()
                return
            }
            
            guard let section = self?.task.messagesList.index(of: msg) else { return }
            self?.messagesCollection.reloadSections([section])
        }
        
    }
}


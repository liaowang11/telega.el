;;; test-topics.el --- Topic tests for telega  -*- lexical-binding:t -*-

(load-file (expand-file-name "test.el" (file-name-directory load-file-name)))

(ert-deftest telega-bot-chat-with-topics-is-forum ()
  "Bot chats with topics enabled should reuse forum topic support."
  (let* ((bot-id 90901)
         (chat-id 90902)
         (users-ht (cdr (assq 'user telega--info)))
         (bot-user `(:@type "user" :id ,bot-id
                             :first_name "Topic"
                             :last_name "Bot"
                             :type (:@type "userTypeBot" :has_topics t)))
         (bot-chat `(:@type "chat" :id ,chat-id
                             :type (:@type "chatTypePrivate" :user_id ,bot-id)
                             :title "Topic Bot")))
    (unwind-protect
        (progn
          (puthash bot-id bot-user users-ht)
          (puthash chat-id bot-chat telega--chats)
          (should (telega-chat-match-p bot-chat 'is-forum)))
      (remhash bot-id users-ht)
      (remhash chat-id telega--chats))))

(ert-deftest telega-msg-open-thread-or-topic-fetches-forum-topic ()
  "Opening a forum topic message should fetch missing topic info."
  (let* ((bot-id 90911)
         (chat-id 90912)
         (topic-id 90913)
         (msg-id 90914)
         (users-ht (cdr (assq 'user telega--info)))
         (bot-user `(:@type "user" :id ,bot-id
                             :first_name "Topic"
                             :last_name "Bot"
                             :type (:@type "userTypeBot" :has_topics t)))
         (bot-chat `(:@type "chat" :id ,chat-id
                             :type (:@type "chatTypePrivate" :user_id ,bot-id)
                             :title "Topic Bot"))
         (msg `(:@type "message" :id ,msg-id :chat_id ,chat-id
                         :topic_id (:@type "messageTopicForum"
                                           :forum_topic_id ,topic-id)))
         (forum-topic `(:@type "forumTopic"
                                :info (:@type "forumTopicInfo"
                                              :chat_id ,chat-id
                                              :forum_topic_id ,topic-id
                                              :icon (:@type "forumTopicIcon"
                                                            :color 0
                                                            :custom_emoji_id "0")
                                              :name "General"))))
    (unwind-protect
        (progn
          (puthash bot-id bot-user users-ht)
          (puthash chat-id bot-chat telega--chats)
          (cl-letf (((symbol-function 'telega--getForumTopic)
                     (lambda (chat forum-topic-id &optional _callback)
                       (should (eq chat bot-chat))
                       (should (= forum-topic-id topic-id))
                       forum-topic))
                    ((symbol-function 'telega-topic-goto)
                     (lambda (topic start-msg-id)
                       (should (eq (telega--tl-type topic) 'forumTopic))
                       (should (eq topic (telega-topic-get bot-chat topic-id)))
                       (should (= start-msg-id msg-id))
                       'topic-opened)))
            (should (eq (telega-msg-open-thread-or-topic msg) 'topic-opened))
            (should (eq (telega--tl-type (telega-msg-topic msg)) 'forumTopic))
            (should (eq (telega-msg-topic msg)
                        (telega-topic-get bot-chat topic-id)))))
      (remhash chat-id telega--chat-topics)
      (remhash bot-id users-ht)
      (remhash chat-id telega--chats))))

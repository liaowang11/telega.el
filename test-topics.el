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

(ert-deftest telega-create-forum-topic-sends-request ()
  "Creating a forum topic should call TDLib with the expected payload."
  (let* ((chat `(:@type "chat" :id 90921))
         (reply `(:@type "forumTopicInfo"
                         :chat_id 90921
                         :forum_topic_id 90922
                         :icon_custom_emoji_id "12345"))
         called-sexp)
    (cl-letf (((symbol-function 'telega-server--call)
               (lambda (sexp &optional _callback _command)
                 (setq called-sexp sexp)
                 reply)))
      (should (equal (telega--createForumTopic chat "Build"
                                             :icon "12345"
                                             :is-name-implicit t)
                     reply))
      (should (equal (plist-get called-sexp :@type) "createForumTopic"))
      (should (= (plist-get called-sexp :chat_id) 90921))
      (should (equal (plist-get called-sexp :name) "Build"))
      (should (equal (plist-get called-sexp :icon_custom_emoji_id) "12345"))
      (should (eq (plist-get called-sexp :is_name_implicit) t)))))

(ert-deftest telega-edit-forum-topic-sends-request ()
  "Editing a forum topic should send TDLib request with changed fields."
  (let* ((chat `(:@type "chat" :id 90931))
         (topic `(:@type "forumTopic"
                          :info (:@type "forumTopicInfo"
                                        :chat_id 90931
                                        :forum_topic_id 90932
                                        :name "Old"))))
    (cl-letf (((symbol-function 'telega-server--send)
               (lambda (sexp &optional _command)
                 (should (equal (plist-get sexp :@type) "editForumTopic"))
                 (should (= (plist-get sexp :chat_id) 90931))
                 (should (= (plist-get sexp :forum_topic_id) 90932))
                 (should (equal (plist-get sexp :name) "New"))
                 (should (equal (plist-get sexp :icon_custom_emoji_id) "98765"))
                 'ok)))
      (should (eq (telega--editForumTopic chat topic
                                         :name "New"
                                         :icon "98765")
                  'ok)))))

(ert-deftest telega-topic-create-fetches-and-opens-created-topic ()
  "Creating a topic should fetch it, cache it and open it."
  (let* ((chat `(:@type "chat" :id 90941
                         :type (:@type "chatTypeSupergroup" :supergroup_id 90940)
                         :title "Forum"))
         (topic-id 90942)
         (forum-topic `(:@type "forumTopic"
                                :info (:@type "forumTopicInfo"
                                              :chat_id 90941
                                              :forum_topic_id ,topic-id
                                              :icon (:@type "forumTopicIcon"
                                                            :color 0
                                                            :custom_emoji_id "0")
                                              :name "Build"))))
    (unwind-protect
        (cl-letf (((symbol-function 'read-string)
                   (lambda (prompt &optional _initial _history _default inherit)
                     (should (string-match-p "Topic Title" prompt))
                     (should-not inherit)
                     "Build"))
                  ((symbol-function 'telega--createForumTopic)
                   (lambda (topic-chat name &rest args)
                     (should (eq topic-chat chat))
                     (should (equal name "Build"))
                     (should-not args)
                     `(:@type "forumTopicInfo"
                               :chat_id 90941
                               :forum_topic_id ,topic-id)))
                  ((symbol-function 'telega--getForumTopic)
                   (lambda (topic-chat forum-topic-id &optional _callback)
                     (should (eq topic-chat chat))
                     (should (= forum-topic-id topic-id))
                     forum-topic))
                  ((symbol-function 'telega-topic-goto)
                   (lambda (topic &optional _start-msg-id)
                     (should (eq topic (telega-topic-get chat topic-id)))
                     'topic-opened))
                  ((symbol-function 'telega-chat--mark-dirty)
                   (lambda (dirty-chat &optional event)
                     (should (eq dirty-chat chat))
                     (should (eq event 'topics))
                     'dirty)))
          (should (eq (telega-topic-create chat) 'topic-opened))
          (should (eq (telega-topic-get chat topic-id) forum-topic)))
      (remhash (plist-get chat :id) telega--chat-topics))))

(ert-deftest telega-topic-toggle-close-rejects-bot-topics ()
  "Closing bot topics should fail until TDLib supports it."
  (let* ((bot-id 90951)
         (chat-id 90952)
         (users-ht (cdr (assq 'user telega--info)))
         (bot-user `(:@type "user" :id ,bot-id
                             :first_name "Topic"
                             :last_name "Bot"
                             :type (:@type "userTypeBot" :has_topics t)))
         (bot-chat `(:@type "chat" :id ,chat-id
                             :type (:@type "chatTypePrivate" :user_id ,bot-id)
                             :title "Topic Bot"))
         (topic `(:@type "forumTopic"
                         :info (:@type "forumTopicInfo"
                                       :chat_id ,chat-id
                                       :forum_topic_id 90953
                                       :icon (:@type "forumTopicIcon"
                                                     :color 0
                                                     :custom_emoji_id "0")
                                       :name "Build"))))
    (unwind-protect
        (progn
          (puthash bot-id bot-user users-ht)
          (puthash chat-id bot-chat telega--chats)
          (should-error (telega-topic-toggle-close topic)
                        :type 'user-error))
      (remhash bot-id users-ht)
      (remhash chat-id telega--chats))))

(ert-deftest telega-topic-toggle-close-updates-forum-topic ()
  "Closing a forum topic should call TDLib and update local state."
  (let* ((chat `(:@type "chat" :id 90954
                         :type (:@type "chatTypeSupergroup" :supergroup_id 90955)
                         :title "Forum"))
         (topic `(:@type "forumTopic"
                         :telega-chat ,chat
                         :info (:@type "forumTopicInfo"
                                       :chat_id 90954
                                       :forum_topic_id 90956
                                       :icon (:@type "forumTopicIcon"
                                                     :color 0
                                                     :custom_emoji_id "0")
                                       :name "Build"))))
    (cl-letf (((symbol-function 'telega--toggleForumTopicIsClosed)
               (lambda (topic-chat forum-topic closed-p)
                 (should (eq topic-chat chat))
                 (should (eq forum-topic topic))
                 (should closed-p)
                 'closed))
              ((symbol-function 'telega-chat--info)
               (lambda (topic-chat &optional _offline-p)
                 (should (eq topic-chat chat))
                 '(:is_forum t)))
              ((symbol-function 'telega-chat--mark-dirty)
               (lambda (dirty-chat &optional event)
                 (should (eq dirty-chat chat))
                 (should (eq event 'topics))
                 'dirty)))
      (should-not (telega-topic-match-p topic 'is-closed))
      (telega-topic-toggle-close topic)
      (should (telega-topic-match-p topic 'is-closed)))))

(ert-deftest telega-topic-delete-confirms-before-deleting ()
  "Deleting a topic should confirm and then call TDLib."
  (let* ((chat `(:@type "chat" :id 90961
                         :type (:@type "chatTypeSupergroup" :supergroup_id 90960)
                         :title "Forum"))
         (topic `(:@type "forumTopic"
                         :info (:@type "forumTopicInfo"
                                       :chat_id 90961
                                       :forum_topic_id 90962
                                       :icon (:@type "forumTopicIcon"
                                                     :color 0
                                                     :custom_emoji_id "0")
                                       :name "Build"))))
    (unwind-protect
        (cl-letf (((symbol-function 'telega-read-im-sure-p)
                   (lambda (prompt)
                     (should (string-match-p "Build" prompt))
                     t))
                  ((symbol-function 'telega--deleteForumTopic)
                   (lambda (topic-chat forum-topic)
                     (should (eq topic-chat chat))
                     (should (eq forum-topic topic))
                     'deleted))
                  ((symbol-function 'telega-chat--mark-dirty)
                   (lambda (dirty-chat &optional event)
                     (should (eq dirty-chat chat))
                     (should (eq event 'topics))
                     'dirty)))
          (puthash (plist-get chat :id) chat telega--chats)
          (telega-topic--ensure topic chat)
          (should (eq (telega-topic-delete topic) 'deleted)))
      (remhash (plist-get chat :id) telega--chat-topics)
      (remhash (plist-get chat :id) telega--chats))))

(ert-deftest telega-topic-delete-works-for-bot-topics ()
  "Deleting a bot topic should use the same forum-topic command path."
  (let* ((bot-id 90971)
         (chat-id 90972)
         (users-ht (cdr (assq 'user telega--info)))
         (bot-user `(:@type "user" :id ,bot-id
                             :first_name "Topic"
                             :last_name "Bot"
                             :type (:@type "userTypeBot" :has_topics t)))
         (bot-chat `(:@type "chat" :id ,chat-id
                             :type (:@type "chatTypePrivate" :user_id ,bot-id)
                             :title "Topic Bot"))
         (topic `(:@type "forumTopic"
                         :info (:@type "forumTopicInfo"
                                       :chat_id ,chat-id
                                       :forum_topic_id 90973
                                       :icon (:@type "forumTopicIcon"
                                                     :color 0
                                                     :custom_emoji_id "0")
                                       :name "Build"))))
    (unwind-protect
        (cl-letf (((symbol-function 'telega-read-im-sure-p)
                   (lambda (_prompt) t))
                  ((symbol-function 'telega--deleteForumTopic)
                   (lambda (topic-chat forum-topic)
                     (should (eq topic-chat bot-chat))
                     (should (eq forum-topic topic))
                     'deleted))
                  ((symbol-function 'telega-chat--mark-dirty)
                   (lambda (dirty-chat &optional event)
                     (should (eq dirty-chat bot-chat))
                     (should (eq event 'topics))
                     'dirty)))
          (puthash bot-id bot-user users-ht)
          (puthash chat-id bot-chat telega--chats)
          (telega-topic--ensure topic bot-chat)
          (should (eq (telega-topic-delete topic) 'deleted)))
      (remhash chat-id telega--chat-topics)
      (remhash bot-id users-ht)
      (remhash chat-id telega--chats))))

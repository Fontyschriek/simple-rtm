(require 'rtm)
(require 'pp)
(require 'cl)

(defvar simple-rtm-lists)
(defvar simple-rtm-tasks)
(defvar simple-rtm-data)

(defgroup simple-rtm-faces nil
  "Customize the appearance of SimpleRTM"
  :prefix "simple-rtm-"
  :group 'faces
  :group 'simple-rtm)

(defface simple-rtm-list
  '((((class color) (background light))
     :foreground "grey30")
    (((class color) (background dark))
     :foreground "grey100"))
  "Face for lists."
  :group 'simple-rtm-faces)

(defface simple-rtm-task
  '((((class color) (background light))
     :foreground "grey60")
    (((class color) (background dark))
     :foreground "grey60"))
  "Face for task names. Other task faces inherit from it."
  :group 'simple-rtm-faces)

(defface simple-rtm-task-priority-1
  '((((class color) (background light))
     :foreground "brightyellow" :inherit simple-rtm-task)
    (((class color) (background dark))
     :foreground "brightyellow" :inherit simple-rtm-task))
  "Face for priority 1 tasks."
  :group 'simple-rtm-faces)

(defface simple-rtm-task-priority-2
  '((((class color) (background light))
     :foreground "brightblue" :inherit simple-rtm-task)
    (((class color) (background dark))
     :foreground "brightblue" :inherit simple-rtm-task))
  "Face for priority 2 tasks."
  :group 'simple-rtm-faces)

(defface simple-rtm-task-priority-3
  '((((class color) (background light))
     :foreground "blue" :inherit simple-rtm-task)
    (((class color) (background dark))
     :foreground "blue" :inherit simple-rtm-task))
  "Face for priority 3 tasks."
  :group 'simple-rtm-faces)

(defface simple-rtm-task-duedate
  '((((class color) (background light))
     :foreground "lightgreen" :inherit simple-rtm-task)
    (((class color) (background dark))
     :foreground "lightgreen" :inherit simple-rtm-task))
  "Face for the task's due date."
  :group 'simple-rtm-faces)

(defface simple-rtm-task-duedate-due
  '((((class color) (background light))
     :foreground "grey100" :background "red" :inherit simple-rtm-task)
    (((class color) (background dark))
     :foreground "grey100" :background "red" :inherit simple-rtm-task))
  "Face for the task's due date if the task is due."
  :group 'simple-rtm-faces)

(dolist (var '(simple-rtm-lists simple-rtm-tasks simple-rtm-data))
  (make-variable-buffer-local var)
  (put var 'permanent-local t))

(defvar simple-rtm-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    (define-key map (kbd "$") 'simple-rtm-reload)
    (define-key map (kbd "* *") 'simple-rtm-task-select-current)
    (define-key map (kbd "* a") 'simple-rtm-task-select-all)
    (define-key map (kbd "* n") 'simple-rtm-task-select-none)
    (define-key map (kbd "* r") 'simple-rtm-task-select-regex)
    (define-key map (kbd ".") 'simple-rtm-redraw)
    (define-key map (kbd "1") 'simple-rtm-task-set-priority-1)
    (define-key map (kbd "2") 'simple-rtm-task-set-priority-2)
    (define-key map (kbd "3") 'simple-rtm-task-set-priority-3)
    (define-key map (kbd "4") 'simple-rtm-task-set-priority-none)
    (define-key map (kbd "<SPC>") 'simple-rtm-task-select-toggle-current)
    (define-key map (kbd "E a") 'simple-rtm-list-expand-all)
    (define-key map (kbd "E n") 'simple-rtm-list-collapse-all)
    (define-key map (kbd "TAB") 'simple-rtm-list-toggle-expansion)
    (define-key map (kbd "c") 'simple-rtm-task-complete)
    (define-key map (kbd "d") 'simple-rtm-task-set-due-date)
    (define-key map (kbd "l") 'simple-rtm-task-set-location)
    (define-key map (kbd "m") 'simple-rtm-task-move)
    (define-key map (kbd "p") 'simple-rtm-task-postpone)
    (define-key map (kbd "r") 'simple-rtm-task-rename)
    (define-key map (kbd "t") 'simple-rtm-task-smart-add)
    (define-key map (kbd "u") 'simple-rtm-task-set-url)
    (define-key map (kbd "y") 'simple-rtm-task-add-note)
    map)
  "The mode map for the simple Remember The Milk interface."
  )

(defun simple-rtm--buffer ()
  (get-buffer-create "*simple-rtm*"))

(defun simple-rtm-mode ()
  (interactive)
  (switch-to-buffer (simple-rtm--buffer))
  (setq major-mode 'simple-rtm-mode
        mode-name "SimpleRTM"
        mode-line-process ""
        truncate-lines t
        buffer-read-only t)
  (use-local-map simple-rtm-mode-map)
  (unless simple-rtm-lists
    (simple-rtm-reload))
  )

(defmacro simple-rtm--save-pos (&rest body)
  (declare (indent 0))
  (let ((list-id (make-symbol "*list-id*"))
        (task-id (make-symbol "*task-id*"))
        (found (make-symbol "*found*")))
    `(let ((,list-id (get-text-property (point) :list-id))
           (,task-id (get-text-property (point) :task-id)))
       ,@body
       (if (member (simple-rtm--overlay-name (simple-rtm--find-list ,list-id))
                   buffer-invisibility-spec)
           (setf ,task-id nil))
       (if (not (simple-rtm--goto ,list-id ,task-id))
           (goto-char (point-min))))))

(defun simple-rtm--goto (list-id &optional task-id)
  (let (found list-at)
    (goto-char (point-min))
    (while (and (not (string= (or (get-text-property (point) :list-id) "") list-id))
                (< (point) (point-max)))
      (forward-line))
    (setf found (string= (or (get-text-property (point) :list-id) "") list-id)
          list-at (point))

    (when (and found task-id)
      (setf found nil)
      (forward-line)
      (while (and (not (string= (or (get-text-property (point) :task-id) "") task-id))
                  (< (point) (point-max)))
        (forward-line))
      (setf found (string= (or (get-text-property (point) :task-id) "") task-id))

      (unless found
        (goto-char list-at)))
    found))

(defun simple-rtm--overlay-name (list)
  (intern (concat "simple-rtm-list-" (getf list :id))))

(defun simple-rtm--render-list-header (list)
  (let ((name (getf list :name)))
    (insert (propertize (concat "["
                                (cond ((not (getf list :tasks)) " ")
                                      ((getf list :expanded) "-")
                                      (t "+"))
                                "] "
                                (if (string= (xml-get-attribute (getf list :xml) 'smart) "1")
                                    (concat "<" name ">")
                                  name)
                                "\n")
                        :list-id (getf list :id)
                        'face 'simple-rtm-list))))

(defun simple-rtm--render-list (list)
  (let ((name (getf list :name))
        list-beg
        (overlay-name (simple-rtm--overlay-name list)))
    (simple-rtm--render-list-header list)
    (setq list-beg (point))
    (dolist (task (getf list :tasks))
      (simple-rtm--render-task task))
    (overlay-put (make-overlay list-beg (point))
                 'invisible overlay-name)
    (unless (getf list :expanded)
      (add-to-invisibility-spec overlay-name))))

(defun simple-rtm--sort-lists (lists)
  (sort lists
        (lambda (l1 l2)
          (let ((l1-smart (xml-get-attribute (getf l1 :xml) 'smart))
                (l2-smart (xml-get-attribute (getf l2 :xml) 'smart)))
            (if (string= l1-smart l2-smart)
                (string< (downcase (getf l1 :name))
                         (downcase (getf l2 :name)))
              (string< l1-smart l2-smart))))))

(defun simple-rtm--cmp (v1 v2)
  (cond ((string< v1 v2) -1)
        ((string= v1 v2) nil)
        (t 1)))

(defun simple-rtm--task-duedate (task &optional default)
  (let ((duedate (xml-get-attribute task 'due)))
    (if (string= duedate "")
        default
      (format-time-string "%Y-%m-%d" (date-to-time duedate)))))

(defun simple-rtm--task< (t1 t2)
  (let* ((t1-task (car (xml-get-children (getf t1 :xml) 'task)))
         (t2-task (car (xml-get-children (getf t2 :xml) 'task)))
         (dueify (lambda (task) (simple-rtm--task-duedate task "9999-99-99")))
         (t1-due (funcall dueify t1-task))
         (t2-due (funcall dueify t2-task))
         (t1-prio (xml-get-attribute t1-task 'priority))
         (t2-prio (xml-get-attribute t2-task 'priority))
         (t1-name (downcase (getf t1 :name)))
         (t2-name (downcase (getf t2 :name))))
    (= -1 (or (simple-rtm--cmp t1-due t2-due)
              (simple-rtm--cmp t1-prio t2-prio)
              (simple-rtm--cmp t1-name t2-name)
              0))))

(defun simple-rtm--render-task (task)
  (let* ((task-node (car (xml-get-children (getf task :xml) 'task)))
         (priority (xml-get-attribute task-node 'priority))
         (priority-str (if (string= priority "N")
                           "  "
                         (propertize (concat "P" priority)
                                     'face (intern (concat "simple-rtm-task-priority-" priority)))))
         (name (getf task :name))
         (url (xml-get-attribute (getf task :xml) 'url))
         (duedate (simple-rtm--task-duedate task-node))
         (today (format-time-string "%Y-%m-%d")))
    (insert (propertize (mapconcat 'identity
                                   (delq nil
                                         (list ""
                                               (if (getf task :marked) "*" " ")
                                               priority-str
                                               (if duedate
                                                   (propertize duedate
                                                               'face (if (string< today duedate)
                                                                         'simple-rtm-task-duedate
                                                                       'simple-rtm-task-duedate-due)))
                                               name
                                               (if (not (string= url "")) url)
                                               ))
                                   " ")
                        :list-id (getf task :list-id)
                        :task-id (getf task :id))
            "\n")))

(defun simple-rtm--find-list (id)
  (if id
      (find-if (lambda (list)
                 (string= (getf list :id) id))
               (getf simple-rtm-data :lists))))

(defun simple-rtm--list-set-expansion (list action)
  (setf (getf list :expanded)
        (cond ((eq action 'toggle) (not (getf list :expanded)))
              ((eq action 'expand) t)
              (t nil))))

(defun simple-rtm-list-toggle-expansion ()
  (interactive)
  (let* ((list-id (get-text-property (point) :list-id))
         (list (or (simple-rtm--find-list list-id)
                   (error "No list found"))))
    (when (> (length (getf list :tasks)) 0)
      (simple-rtm--list-set-expansion list 'toggle)
      (simple-rtm-redraw))))

(defun simple-rtm-list-expand-all ()
  (interactive)
  (dolist (list (getf simple-rtm-data :lists))
    (simple-rtm--list-set-expansion list 'expand))
  (simple-rtm-redraw))

(defun simple-rtm-list-collapse-all ()
  (interactive)
  (dolist (list (getf simple-rtm-data :lists))
    (simple-rtm--list-set-expansion list 'collapse))
  (simple-rtm-redraw))

(defun simple-rtm--task-set-marked (task action)
  (setq task (simple-rtm--modify-task (getf task :id)
                                      (lambda (task)
                                        (plist-put task :marked (cond ((eq action 'toggle) (not (getf task :marked)))
                                                                      ((eq action 'mark) t)
                                                                      (t nil)))))))

(defun simple-rtm-task-select-toggle-current ()
  (interactive)
  (let* ((task-id (get-text-property (point) :task-id))
         (task (simple-rtm--find-task task-id)))
    (when task
      (simple-rtm--task-set-marked task 'toggle)
      (simple-rtm-redraw)))
  (beginning-of-line)
  (forward-line))

(defun simple-rtm-reload ()
  (interactive)
  (with-current-buffer (simple-rtm--buffer)
    (let* ((task-node-handler
            (lambda (task-node)
              (list :name (decode-coding-string (xml-get-attribute task-node 'name) 'utf-8)
                    :id (xml-get-attribute task-node 'id)
                    :list-id list-id
                    :marked nil
                    :xml task-node)))
           (list-node-handler
            (lambda (list-node)
              (let ((list-id (xml-get-attribute list-node 'id)))
                (list :name (decode-coding-string (xml-get-attribute list-node 'name) 'utf-8)
                      :id list-id
                      :expanded nil
                      :xml list-node
                      :tasks (sort (mapcar task-node-handler
                                           (xml-get-children (car (remove-if (lambda (task-list-node)
                                                                               (not (string= list-id (xml-get-attribute task-list-node 'id))))
                                                                             simple-rtm-tasks))
                                                             'taskseries))
                                   'simple-rtm--task<))))))
      (unless simple-rtm-lists
        (setq simple-rtm-lists (rtm-lists-get-list)))
      (unless simple-rtm-tasks
        (setq simple-rtm-tasks (rtm-tasks-get-list nil "status:incomplete")))
      (setq simple-rtm-data (list :lists (simple-rtm--sort-lists (mapcar list-node-handler simple-rtm-lists))))
      (simple-rtm-redraw)
      (simple-rtm-list-expand-all))))

(defun simple-rtm-redraw ()
  (interactive)
  (with-current-buffer (simple-rtm--buffer)
    (simple-rtm--save-pos
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq buffer-invisibility-spec nil)
        (dolist (list (getf simple-rtm-data :lists))
          (simple-rtm--render-list list))))))

(provide 'simple-rtm)
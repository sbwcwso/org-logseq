;;; org-logseq.el --- for logseq  -*- lexical-binding: t; -*-

;; Author: Lijunjie <lijunjie199502@gmail.com>
;; URL: https://github.com/sbwcwso/org-logseq
;; Package-Version: 20230228.2339
;; Version: 0.0.5
;; Package-Requires: ((dash "2.11.0") (org "9.0.0"))


;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Make logseq work easier in Emacs

;;; Code:

(require 'ol)
(require 'org-element)

(defgroup org-logseq nil
  "Logseq capbility in Org Mode."
  :group 'org)

(defcustom org-logseq-dir nil
  "Path of logseq notes."
  :group 'org-logseq)

(defcustom org-loseq-graph nil
  "Name of logseq graph."
  :group 'org-logseq)

(defcustom org-logseq-graph-index 0
  "Window number of the graph"
  :group 'org-logseq)

(defcustom org-logseq-graph-window-table (make-hash-table :test 'equal)
  "window index table of graph, used for org-logseq-open-external")

(defcustom org-logseq-create-journal-command nil
  "The command to create journal"
  :group 'org-logseq)

(defcustom org-logseq-new-page-p nil
  "Non-nil means creating a page if not exist."
  :group 'org-logseq)

(defcustom org-logseq-block-ref-overlay-p nil
  "Non-nil means to enable block ref by default."
  :group 'org-logseq)
(make-variable-buffer-local 'org-logseq-block-ref-overlay-p)

(defcustom org-logseq-block-embed-overlay-p nil
  "Non-nil means to enable block ref by default."
  :group 'org-logseq)

(make-variable-buffer-local 'org-logseq-block-embed-overlay-p)


;; deprecate
(defun org-logseq-grep-query (page-or-id)
  "Return grep result for searching PAGE-OR-ID in `org-logseq-dir'."
  (let ((type (car page-or-id))
        (query (cdr page-or-id)))
    (format (pcase type
              ('page "rg -ni --no-heading -m 1 --type org -g '!.git' -g '!logseq' -g '!assets' '^#\\+(TITLE|ALIAS): *%s$' %s" )
              ('id "rg -ni --no-heading -m 1 --type org -g '!.git' -g '!logseq'  -g '!assets' ':id: *%s' %s"))
            query (shell-quote-argument org-logseq-dir))))

;; deprecate
(defun org-logseq-open-file-at-line-number (file-name line-number)
  "Open the given logseq file at LINE-NUMBER.
if the FILE-NAME is current buffer, jump to the line."
  (if (string-equal file-name (buffer-file-name))
      (progn
        (org-goto-line line-number)
        (when (equal (line-number-at-pos) line-number)
          (evil-open-fold)
          (org-goto-line line-number)))
    (org-open-file file-name t line-number))
  (evil-close-fold)
  (org-fold-show-children))

(defun org-logseq-copy-create-id ()
  "Copy id at current point with (()) around it, if id does not exist, create a new one."
  (interactive)
  (let ((id (org-id-get-create)) res)
    (setq res (format "((%s))" id))
    (kill-new res)
    ;; (xclip res)  # TODO make sure this works
    res))

(defun org-logseq-set-heading ()
  "Set heading according to the level of current point"
  (interactive)
  (let ((head-level (org-outline-level)))
    (org-set-property "heading" (number-to-string head-level))
    (org-cycle-hide-drawers 'all)
    )
  )

(defun org-logseq-copy-ids-from-region ()
  "Copy ids from region."
  (interactive)
  (save-excursion
    (let ((start (region-beginning))
          (end (region-end))
          (headings '())
          res)
      (goto-char start)
      (org-next-visible-heading 0)
      (while (< (point) end)
        (push (concat
         (make-string (+ (org-outline-level) 2) ?*) " "
         (org-logseq-copy-create-id)) headings)
        (org-next-visible-heading 1))
      (setq res (string-join (reverse headings) "\n"))
      (message res)
      (kill-new res)
      res)))

(defun org-logseq-copy-ids-from-parents ()
  "Copy ids from the parent title."
  (interactive)
  (save-excursion
    (save-excursion (let ((headings '())
          res)
      (if (region-active-p)
          (goto-char (region-beginning))
          (deactivate-mark)
          )
      (while (org-up-heading-safe)
        (push (concat
         (make-string (+ (org-outline-level) 2) ?*) " "
         (org-logseq-copy-create-id)) headings)
        )
      (setq res (string-join headings "\n"))
      (message res)
      (kill-new res)
      res))))

(defun org-logseq-copy-ids-from-region-with-parents ()
  "Copy ids from region with the parent's id."
  (interactive)
  (let ((res
         (concat (org-logseq-copy-ids-from-parents) "\n"
                 (org-logseq-copy-ids-from-region))))
    (message res)
    (kill-new res)
    res
    )
  )


(defun is-uuid (s)
  "Return non-nil if S is a uuid, otherwise nil."
  ((lambda(s)(and(eq(string-bytes s)36)(let((l(string-to-list s))(i 0)(h '(8 13 18 23))(v t))(dolist(c l v)(set'v(and v(if(member i h)(and v(eq c 45))(or(and(> c 47)(< c 58))(and(> c 64)(< c 91))(and(> c 96)(< c 123))))))(set'i(+ i 1)))))) s))

(defun org-logseq-get-begin-value (key)
  "Get begin #+KEY:value of org."
  (cadar (org-collect-keywords (list key))))

(defun org-logseq-set-begin-value (key value)
  "Set the value of the first occurence of #+KEY: VALUE add it at the beginning of file if there is none."
  (let* ((key (concat "#+" key ": "))
        (new-key-value (concat key value)))
    (save-excursion
      (goto-char (point-min))
      (if (re-search-forward
          (concat (regexp-quote key) "\.\*\$") nil t)
          (replace-match new-key-value nil nil)
        (insert (concat new-key-value "\n"))))))

(defun org-logseq-get-block-id ()
  "Return a cons: \"('id . id)\" at point."
  (save-excursion
    (when-let* ((prev-bracket (search-backward-regexp "((" (line-beginning-position) t)))
      (let* ((next-bracket (search-forward-regexp "))" (line-end-position) t))
             (id (buffer-substring-no-properties
                  (+ prev-bracket 2) (- next-bracket 2))))
        (cons 'id id)))))

(defun org-logseq-get-link ()
  "Return a cons: \"('type . link)\" at point. The type can be 'url,'xdg, 'page, denoting the link type."
  (save-excursion
    (let ((context (org-element-context)) link)
      (when (eq 'link (car context))
        (setq link (org-element-property :raw-link context))
        (cond ((string-match "\\(?:https?\\)" link)
               (cons 'url link))
              ((string-match "\\(?:logseq?\\)" link)
               (cons 'xdg link))
              (t (cons 'page link)))))))



(defun org-logseq-get-block-ref-from-overlay ()
  "Return \"('id . uuid)\" if point is a overlay created by org-logseq."
  (when-let ((ov (ov-at))
             (create-by-org-logseq-flag (eq (ov-val ov 'category) 'block-ref)))
    (cons 'overlay (ov-val ov 'block-uuid))))

(defun org-logseq-get-file-name-from-title (title-name)
  "Return file name with path by the TITLE-NAME."
  (if (string-match (rx string-start (group (= 4 digit)) "-"
                        (group (= 2 digit)) "-" (group (= 2 digit)) string-end) title-name)
      (expand-file-name (concat "journals/"
                                (match-string 1 title-name) "_"
                                (match-string 2 title-name) "_"
                                (match-string 3 title-name) ".org")
                        org-logseq-dir)
    (expand-file-name (concat
                       "pages/" (string-replace "/" "___" title-name) ".org")
                      org-logseq-dir)))

(defun org-logseq-open-page-inside (title)
  "Open logseq by TITLE inside Emacs."
  (let (file-name)
    (if (string-match (rx string-start (group (= 4 digit)) "-"
                          (group (= 2 digit)) "-" (group (= 2 digit)) " " (or "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday") string-end) title)
        (setq file-name (concat "journals/" (match-string 1 title) "_"
                                (match-string 2 title) "_" (match-string 3 title)
                                ".org"))
      (setq file-name (concat "pages/" (string-replace "/" "___" title) ".org")))
    (setq file-name (expand-file-name file-name org-logseq-dir))
    (if (file-exists-p file-name)
        (org-open-file file-name t)
      (org-logseq-create-new-page title))
    ))

(defun org-logseq-update-id-locations ()
  "Update id locations in logseq directories."
  (interactive)
  (org-id-update-id-locations
   (append
    (directory-files (expand-file-name "journals" org-logseq-dir) t ".*org")
    (directory-files (expand-file-name "pages" org-logseq-dir) t ".*org"))))

(defun org-logseq-find-id-file (id)
  "Find ID location by 'org-id-find-id-file'.
If can't find update the id locations and try again."
  (let ((file-name (file-truename (org-id-find-id-file id))))
    (if file-name
        file-name
      (progn
        (message "Not found id, update the id locations.")
        (org-logseq-update-id-locations)
        (setq file-name (file-truename (org-id-find-id-file id)))
        (if file-name
            file-name
          (user-error "Can not find id: \"%s\"" id))))))

(defun org-logseq-goto-id (id)
  "Goto ID."
  (let ((file-name (org-logseq-find-id-file id)))
    (if (not (string-equal (buffer-file-name) file-name))
        (find-file-other-window file-name))
    (org-id-goto id)
    (org-fold-hide-subtree)
    (org-show-children)))

(defun  org-logseq-activate-window-by-graph (&optional target-graph-name)
  (interactive)
  (let* ((command "xdotool search --onlyvisible --classname  \"logseq\"")
         (output (shell-command-to-string command))
         (window-ids-unsorted (split-string output "\n" t))
         (window-ids (sort window-ids-unsorted
                           (lambda (a b)
                             (< (string-to-number a) (string-to-number b))))))  ; 将字符串转换为数值并排序
    (let* ((graph-name (if target-graph-name target-graph-name org-logseq-graph))
          (target-id (if (= (length window-ids) 1)
                         (car window-ids)  ; 如果只有一个窗口，忽略索引参数
                       (nth ( let ((index (gethash graph-name org-logseq-graph-window-table)))
                              (if index
                                  index
                                0)
                             )
                            window-ids))))  ; 如果有多个窗口，使用索引选择窗口
      (if target-id
          (progn
            (shell-command (format "xdotool windowactivate %s" target-id))
            (message "Activated window ID: %s" target-id))
        (message "No window found with the title '%s'" title)))))



(defun org-logseq-open-external (title-or-id)
  "Change logseq page through xdg-open by TITLE-OR-ID.
But not change the keyboard focus.
In order to use this function, you need to manually open logseq in advance."
  ;; (message (concat "xdg-open \"logseq://graph/Logseq_notes?" title-or-id "\""))
  (let ((command (concat "xdg-open \"logseq://graph/" org-logseq-graph "?" title-or-id "\"")))
    (message "%s" command)
    (shell-command command))
  (sleep-for 1)

  ;; (message (concat "xdg-open \"logseq://graph/" org-logseq-graph "?" title-or-id "\""))
  ;; (shell-command
  ;;  (concat "xdg-open \"logseq://graph/" org-logseq-graph "?" title-or-id "\""))

  ;; (shell-command-to-string "xdotool getwindowfocus")
  ;; (shell-command (format "currentwindow=$(xdotool getwindowfocus);xdg-open 'logseq://graph/Logseq_notes?%s';xdotool windowactivate $currentwindow" title-or-id))
  (org-logseq-activate-window-by-graph)
  (let ((command (concat "xdotool search --name " (shell-quote-argument (frame-parameter nil 'name))
                        " windowactivate %1")))
    (setq command (replace-regexp-in-string "\\+" "\\\\+" command))
    (message "%s" command)
    (shell-command command)
    )
  ;; (shell-command
  ;;  (concat "xdotool search --name " (shell-quote-argument (frame-parameter nil 'name))
  ;;          " windowactivate %1"))
   ;; (format "xdotool search --name '%s' windowactivate %%1" (frame-parameter nil 'name))
           ;; )
  ;; (call-process-shell-command
  ;;  (concat "xdg-open \"logseq://graph/Logseq_notes?" title-or-id "\";" "xdotool search --name \"" (shell-quote-argument (frame-parameter nil 'name))
  ;;          "\" windowactivate %1"))
  )

(defun org-logseq-open-external-by-uuid (block-id)
  "Open logseq by BLOCK-ID."
  (org-logseq-open-external (concat "block-id=" block-id)))

(defun org-logseq-get-link-at-point ()
  "Return (type link) at current point."
  (or
   (org-logseq-get-block-ref-from-overlay)
   (org-logseq-get-link)
   (org-logseq-get-block-id)
   ))

(defun org-logseq-create-new-page (title-name)
    "Create a new org file in pages directory according to TITLE-NAME."
    (let ((page-name
           (expand-file-name (concat
                              "pages/" (string-replace "/" "___" title-name) ".org")
                             org-logseq-dir)))
      (if (y-or-n-p (format "The file \"%s\" doesn't exist, create it or not?" page-name))
          (progn
            (find-file-other-window page-name)
            (org-logseq-set-begin-value "title" title-name))
        (message (format "The file \"%s\" doesn't exist." page-name)))))

;;;###autoload
(defun org-logseq-evil-close-fold ()
  "Set the heading's collapsed property to true after close fold."
  (interactive)
  (evil-close-fold)
  (org-set-property "collapsed" "true")
  (org-cycle-hide-drawers 'all))

;;;###autoload
(defun org-logseq-evil-open-fold ()
  "Set the heading's collapsed property to false after open fold."
  (interactive)
  (org-show-children)
  (org-delete-property "collapsed")
  (org-cycle-hide-drawers 'all))

;;;###autoload
(defun org-logseq-evil-close-folds ()
  "Close all folds by 'evil-close-folds', and set the first level's collapsed property to ture."
  (interactive)
  (evil-close-folds)
  (org-map-entries '(org-set-property "collapsed" "true") "LEVEL=1"))

;;;###autoload
(defun org-logseq-url-hexify-string (str)
  "URL encode a string in a way similar to JavaScript's encodeURIComponent."
  (apply 'concat
         (mapcar (lambda (char)
                   (let ((ascii (char-to-string char)))
                     (if (or (and (>= char ?A) (<= char ?Z))  ; A-Z
                             (and (>= char ?a) (<= char ?z))  ; a-z
                             (and (>= char ?0) (<= char ?9))  ; 0-9
                             (member char '(?- ?_ ?. ?~)))   ; - _ . ~
                         ascii
                       (format "%%%02X" char))))
                 str)))

(defun org-logseq-open-external-by-title (&optional title)
  "Open logseq page by current buffer's #+title or TITLE."
  (interactive)
  ;; TODO handel the situation that there is no page named title.
  (org-logseq-set-title)
  (if (not (when-let ((title (org-logseq-url-hexify-string (or title (org-logseq-get-begin-value "title"))))
                      (title-link (concat "page=" title)))
             (org-logseq-open-external title-link)
             ))
      (message "There is not #+TITLE or #+title property in current buffer.")))

;;;###autoload
(defun org-logseq-open-current-block-external ()
  "Open current block external.
If there is not uuid of current block, send a message."
  (interactive)
  (let ((uuid (org-id-get)))
    (if uuid
        (org-logseq-open-external-by-uuid uuid)
      (message "There is no uuid of current block!"))))

;;;###autoload
;; TODO intergate with org-logseq-open-link
(defun org-logseq-open-external-at-point ()
  "Open logseq page by block-id."
  (interactive)
  (message
   (catch 'exit
     (let (type-link type link)
       ;; https://codegolf.stackexchange.com/a/66501
       (save-excursion
         (while (or (setq type-link (org-logseq-get-link-at-point))
                    (org-up-heading-or-point-min))
           (if type-link
               (progn
                 (setq type (car type-link))
                 (setq link (cdr type-link))
                 (pcase type
                   ('url
                    (browse-url link)
                    (throw 'exit "Open url."))
                   ('xdg
                    (shell-command
                     (concat "xdg-open \"" link "\""))
                    (sleep-for 1)
                    (let ((graph-name (when (string-match "logseq://graph/\\(.*\\)\\?" link)
                                        (match-string 1 link))
                                      ))
                      (org-logseq-activate-window-by-graph graph-name)
                      (message link)
                      (shell-command
                       (concat "xdotool search --name " (shell-quote-argument (frame-parameter nil 'name))
                               " windowactivate %1")
                       )
                          )
                    
                    (throw 'exit "open logseq link")
                    )
                   ('page (org-logseq-open-external-by-title link)
                          (throw 'exit "Open page according to current block or it's parent's block."))
                   (_ (org-logseq-open-external-by-uuid link)
                      (throw 'exit "Open block-id at current block or it's parent's block")
                      )))))
         (org-logseq-open-external-by-title)
         (throw 'exit "Open current page in logseq."))))))

(defun org-logseq-update-file-timestamp ()
  "Update current buffer's last-update-time property."
  (interactive)
    (org-logseq-set-begin-value "last-update-time" (current-time-string))
)

;;;###autoload
(defun org-logseq-update-selected-file-timestamp ()
  "Update logseq files last-update-time property."
  (interactive)
  (save-buffer)
  (save-excursion
    (set-buffer logseq-current-buffer)
    (org-logseq-set-begin-value "last-update-time" (current-time-string))
    (save-buffer)))

;;;###autoload
(defun org-logseq-select-current-buffer ()
  "Set logseq-current-bufer to current buffer."
  (interactive)
  (setq logseq-current-buffer (current-buffer))
  (message "logseq-current-buffer set to %s" (buffer-name)))

;;;###autoload
(defun org-logseq-set-title ()
  "Set the #+title property according to current logseq buffer filename."
  (interactive)
  (let ((title (org-get-title)) file-name)
    (if title
        (message "The #+title property already exists")
      (progn
        (setq file-name (file-name-base (buffer-file-name)))
        (if (string-match (rx string-start (group (= 4 digit)) "_" (group (= 2 digit))
                              "_" (group (= 2 digit)) string-end)
                          file-name)
            (progn
              (let* ((year (string-to-number (match-string 1 file-name)))
                     (month (string-to-number (match-string 2 file-name)))
                     (day (string-to-number (match-string 3 file-name)))
                     (day-of-week
                      (nth (org-day-of-week day month year)
                           '("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"))))
                (setq title (format "%04d-%02d-%02d %s" year month day day-of-week))
                (message (format "Current buffer is a journal file, set the title to %s" title))))
          (progn
            (setq title (string-replace "___" "/" file-name))
            (message (format "Current buffer is a page file, set the title to %s" title))))
        (org-logseq-set-begin-value "title" title)))))

;;;###autoload
(defun org-logseq-open-at-point-inside ()
  "Open link at point in Emacs or browser, supports url, id, page."
  (interactive)
  (when-let ((type-link (org-logseq-get-link-at-point)))
    (let ((type (car type-link))
          (link (cdr type-link)))
      (pcase type
        ('url (browse-url link))
        ('page (org-logseq-open-page-inside link))
        (_ (org-logseq-goto-id link))))))

;;;###autoload
(defun org-logseq-open-at-point-external ()
  "Open link at point in Logseq or browser, suports url, id, page."
  (interactive)
  (when-let ((type-link (org-logseq-get-link-at-point)))
    (let ((type (car type-link))
          (link (cdr type-link)))
      (pcase type
        ('url (browse-url link))
        ('page (org-logseq-open-external-by-title link))
        (_ (org-logseq-open-external-by-uuid link))))))

;;;###autoload

;;;###autoload

;;; Logseq id overlays

;;;###Variable for another functions.
;; (defvar org-logseq-block-ref-re "((\\([a-zA-Z0-9-]+\\)))")
(defvar org-logseq-block-ref-re
  (rx "((" (group (= 8 alnum) "-"
                  (= 3 (= 4 alnum) "-")
                  (= 12 alnum)) "))"))

(defun org-logseq-replace-todo (heading)
  "If HEADING start with TODO DO DONE, replace them."
  (while (string-match (rx word-start (| "TODO" "DOING" "DONE" "CANCELED") word-end " ") heading)
    (setq heading
          (concat (substring heading nil (match-beginning 0))
                  (substring heading (match-end 0) nil))))
  heading)

(defun org-logseq-replace-link (heading)
  "If HEADING contain [[link][title],  only show title."
  (while (string-match "\\[\\[.+\\]\\[\\(.+\\)\\]\\]" heading)
    (setq heading
          (concat (substring heading nil (match-beginning 0))
                  "🌐"
                  (match-string 1 heading)
                  (substring heading (match-end 0) nil))))
  heading)

(defun org-logseq-make-block-ref-overlays ()
  "Insert ovelays at ref."
  (interactive)
  ;; (ov-clear)
  (let (ov uuid begin end heading-text)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward org-logseq-block-ref-re nil t)
        (setq uuid (match-string 1))
        (setq begin (match-beginning 0))
        (setq end (match-end 0))
        (if (and (is-uuid uuid)
                 (not (ov-in begin end)))
            (progn
              (setq ov (ov-make  begin end))
              (setq heading-text (org-logseq-get-block-ref-content uuid))
              (ov-set ov
                      'category 'block-ref
                      'display heading-text
                      'prev-display heading-text
                      'block-uuid uuid
                      'evaporate t
                      ;; 'target heading-text
                      'face 'org-inline-src-block
                      'front-sticky t
                      'rear-sticky t
                      'cursor-sensor-functions (list #'org-logseq-ov-cursor-sensor))
              ;; (ov-placeholder ov)
              ))))))

(defun org-logseq-ov-cursor-sensor (_window position state)
  "Change the display of overlay at POSITION in WINDOW accordint to the STATE."
  (setq disable-point-adjustment t)
  (let (( ov (ov-at
              (pcase state
                ('entered nil)
                ('left position)
                )
              )))
    (if (and ov (eq (ov-val ov 'category) 'block-ref))
        (pcase state
          ('entered
           (ov-set ov 'display nil)
           ;; (set-mark (ov-end ov))
           ;; (goto-char (ov-beg ov))
           ;; (activate-mark)
           (goto-char (- (ov-end ov) 3))
           (message "%S" (org-logseq-find-id-file (ov-val ov 'block-uuid)))
           )
          ('left
           (save-excursion (ov-set ov 'display (org-logseq-get-block-ref-content (ov-val ov 'block-uuid))))
           )))))

(defun org-logseq-get-block-ref-content (uuid)
  "Return the content of the given UUID."
  (when-let ((file-name (org-logseq-find-id-file uuid)))
    (save-window-excursion
      (with-current-buffer (find-file-noselect file-name)
        (org-id-goto uuid)
        (let ((result (org-no-properties (org-get-heading))))
          (dolist (func  '(org-logseq-replace-link
                           org-logseq-replace-block-ref
                           org-logseq-replace-todo))
            (setq result (funcall func result)))
          result)))))

(defun org-logseq-replace-block-ref (heading)
  "If HEADING contain ((uuid)), replace it with the heading text."
    (while (string-match org-logseq-block-ref-re heading)
      (let ((uuid (match-string 1 heading))
            (end (match-end 0)))
        (if (is-uuid uuid)
          (setq heading
                (concat (substring heading nil (match-beginning 0))
                        (org-logseq-get-block-ref-content uuid)
                        (substring heading end nil)
                        )))))
  heading)

;;;; Personal use


;; xdotools send keys.


(defun org-logseq-surround (char)
  "Wrap of 'evil-surround-region' with CHAR argument, ignore the inline code, inline verbatim, and inline formulas."
  (save-excursion
    (let* ((start (region-beginning))
           (pos (region-end))
           (patterns '("=\\([^=]*\\)=" "~\\([^~]*\\)~" "\\\\\\([^\\]*\\\\\\)")))
      (goto-char pos)
      (while (re-search-backward (mapconcat 'identity patterns "\\|") start t)
        (let ((match-end (match-end 0))
              (match-start (match-beginning 0)))
          ;; 向后跳过空格和标点符号
          (goto-char match-end)
          (while (looking-at "[[:space:][:punct:]]")
            (setq match-end (1+ match-end))
            (forward-char 1))
          ;; 向前跳过空格和标点符号
          (goto-char match-start)
          (while (and (> match-start start) (string-match-p "[[:space:][:punct:]]" (char-to-string (char-before match-start))))
            (setq match-start (1- match-start)))
          (if (> pos match-end)
              (evil-surround-region match-end pos 'block char))
          (setq pos match-start)))
      (if (> pos start)
          (evil-surround-region start pos 'block char)))))



(defun org-logseq-send-keys (key)
  "Send KEY to the logseq window."
  ;; (shell-command (format  "currentwindow=$(xdotool getwindowfocus);xdotool windowactivate --sync $(xdotool search --onlyvisible --class logseq|tail -1); xdotool key %s;xdotool windowactivate $currentwindow" key))
  (org-logseq-activate-window-by-graph org-logseq-graph)
  (shell-command (format "xdotool key %s;" key))
  (shell-command
   (concat "xdotool search --name " (shell-quote-argument (frame-parameter nil 'name))
           " windowactivate %1"))
  )

(defun org-logseq-page-up ()
  "Send Page_Up key to the logseq."
  (interactive)
  (org-logseq-send-keys "Page_Up"))

(defun org-logseq-page-down ()
  "Send Page_Up key to the logseq."
  (interactive)
  (org-logseq-send-keys "Page_Down"))

(defun org-logseq-home ()
  "Send home key to the logseq."
  (interactive)
  (org-logseq-send-keys "Home"))

(defun org-logseq-end ()
  "Send End key to the logseq."
  (interactive)
  (org-logseq-send-keys "End"))

;; (defvar org-logseq-overlay-map
;;   (let ((map (make-sparse-keymap)))
;;     (define-key map "RET" 'org-logseq-open-link)
;;     map))

;;;; Time-related

(defvar org-logseq-bonus-time 0)
(defvar org-logseq-pomodoro-time 0)
(defvar org-logseq-time-re
  (rx (+ (| (group-n 3 (group-n 1 (? "-") (+ digit)) "h" (? " ")) (group-n 4 (group-n 2 (? "-") (+ digit)) "min")))
   ))

(defvar org-logseq-habits '("nofap" "nogame" "novideo"))
(defvar org-logseq-habit-bonus-time
  '(
    ("nofap" . 10)
    ("nogame" . 10)
    ("novideo" . 10)
    ))

(defvar org-logseq-habit-punish-time
  '(
    ("nofap" . 60)
    ("nogame" . 60)
    ("novideo" . 60)
    ))


(defun org-logseq-minutes-to-string (minutes)
  "Convert MINUTES to hour minute format."
  (let* ((sign (if (> minutes 0) 1 -1))
         (minutes (abs minutes))
         (hours (/ minutes 60))
         (minutes (- minutes (* 60 hours))))
    (format "%s%s%s"
            (if (= sign -1) "-" "")
            (if (> hours 0) (format "%dh " hours) "")
            (if (> minutes 0) (format "%dmin" minutes) ""))))

(defun org-logseq-get-minutes-from-string (time-string)
  "Get minutes for TIME-STRING(Like 2h 5min)."
  (string-match org-logseq-time-re time-string)
  (let ((hours   (string-to-number (or (match-string 1 time-string) "0")))
        (minutes (string-to-number (or (match-string 2 time-string) "0"))))
    (+ minutes (* 60 hours))))

(defun org-logseq-update-bonus-time ()
  "Update logseq journal bonus time."
  (interactive)
  (setq org-logseq-bonus-time 0)
  (org-map-entries
   '(progn
      (let ((punish-time (org-entry-get (point) ".punish"))
            (bonus-time (org-entry-get (point) ".bonus")))

        (if punish-time
            (progn
              (org-entry-delete (point) ".punish")
              (org-entry-put (point) "punish" punish-time)))
        (if bonus-time
            (progn
              (org-entry-delete (point) ".bonus")
              (org-entry-put (point) "bonus" bonus-time)))
        )
      ) "TODO=\"TODO\"")

  (org-map-entries
   '(progn
      (let ((punish-time (org-entry-get (point) "punish"))
            (bonus-time (or (org-entry-get (point) ".bonus")
                             (org-entry-get (point) "bonus"))))

        (if punish-time
            (progn
              (org-entry-delete (point) "punish")
              (org-entry-put (point) ".punish" punish-time)))
        (if bonus-time
            (progn
              (setq org-logseq-bonus-time (+ org-logseq-bonus-time (org-logseq-get-minutes-from-string bonus-time)))
              (org-entry-delete (point) ".bonus")
              (org-entry-put (point) "bonus" bonus-time)))
        )
      ) "TODO=\"DONE\"")

  (org-map-entries
   '(progn
      (let ((punish-time  (or (org-entry-get (point) ".punish")
                              (org-entry-get (point) "punish")))
            (bonus-time (org-entry-get (point) "bonus")))

        (if punish-time
            (progn
              (setq org-logseq-bonus-time (+ org-logseq-bonus-time (org-logseq-get-minutes-from-string punish-time)))
              (org-entry-delete (point) ".punish")
              (org-entry-put (point) "punish" punish-time)))
        (if bonus-time
            (progn
              (org-entry-delete (point) "bonus")
              (org-entry-put (point) ".bonus" bonus-time)))
        )
      ) "TODO=\"CANCELLED\"")

  (dolist (habit org-logseq-habits)
    (if (string-equal (org-logseq-get-begin-value habit) "😭")
        (setq org-logseq-bonus-time
              (- org-logseq-bonus-time
                 (cdr (assoc habit org-logseq-habit-punish-time))))
      (if (string-equal (org-logseq-get-begin-value habit) "😃")
          (setq org-logseq-bonus-time
                (+ org-logseq-bonus-time
                   (cdr (assoc habit org-logseq-habit-bonus-time))))))
    )
  (org-logseq-set-begin-value "bonus_time" (org-logseq-minutes-to-string org-logseq-bonus-time)))


(defun org-logseq-update-pomodoro ()
  "Update journal's pomodoro time."
  (interactive)
  (setq org-logseq-pomodoro-time 0)
  (org-map-entries
   '(progn
      (let ((time-string (org-entry-get (point) "pomodoro")))
        (setq org-logseq-pomodoro-time
              (+ org-logseq-pomodoro-time (org-logseq-get-minutes-from-string time-string)))
        ))
   (concat "pomodoro={" org-logseq-time-re "}"))
  (org-logseq-set-begin-value "pomodoro" (org-logseq-minutes-to-string org-logseq-pomodoro-time))
  )

(defun org-logseq-update-total-time ()
  "Update the total time."
  (interactive)
  (org-logseq-update-bonus-time)
  (org-logseq-update-pomodoro)
  (org-logseq-set-begin-value
   "total"
   (org-logseq-minutes-to-string (+ org-logseq-bonus-time org-logseq-pomodoro-time)))
  )

(defun org-logseq-set-pomodoro-time (hour minute)
  "Update pomodoro time at point."
  (interactive
   (list (read-number "Hour: " 0) 
         (read-number "Minute: " 35)))
  (org-entry-put (point) "pomodoro" (format "%dh %dmin" hour minute))
  (org-todo "DONE")
  (org-logseq-update-total-time)
  )

(defun org-logseq-set-bonus-time (hour minute)
  "Update pomodoro time at point."
  (interactive
   (list (read-number "Hour: " 0) 
         (read-number "Minute: " 10)))
  (org-entry-put (point) "bonus" (format "%dh %dmin" hour minute))
  (org-todo "DONE")
  (org-logseq-update-total-time)
  )

(defun org-logseq-coallapsed-by-properties ()
  "Coallapsed head by the collapsed properties at point."
  (save-excursion
    (if (string-equal "true" (org-entry-get (point) "collapsed"))
        (progn
          (evil-close-fold)
          (org-cycle-hide-drawers 'all)
          )
      (progn
        (org-show-children)
        (org-cycle-hide-drawers 'all)
        )
    )
  ))

(defun org-logseq-same-line-p (point1 point2)
  "Check if POINT1 and POINT2 are on the same line."
  (eq (line-number-at-pos point1) (line-number-at-pos point2)))

(defun org-logseq-update-collapsed-state ()
  "Update the whole collapsed state in current buffer."
  (interactive)
  (save-excursion
    (let ((old-point (point-max)))
      (goto-char (point-min))
      (while (not (org-logseq-same-line-p (point) old-point))
        (if (org-at-heading-p)
            (org-logseq-coallapsed-by-properties))
        (org-next-visible-heading 1)
        )))
  )


(defun org-logseq-switch-to-today ()
    "Switch to today's journal.
If today's journal does not exists, switch to yesterday's journal."
    (interactive)
    (let ((today-journal-name (org-logseq-get-file-name-from-title (format-time-string "%Y-%m-%d"))))
      (if (not (file-exists-p today-journal-name))
          (shell-command org-logseq-create-journal-command))
      (find-file today-journal-name)
      (org-logseq-open-external-by-title)))


(defun org-logseq-switch-to-previous-day ()
  "Switch to the previous day's log file with format YYYY_MM_DD.org."
  (interactive)
  (let* ((current-filename (buffer-file-name))
         (date-string (replace-regexp-in-string "_" "-" (file-name-base current-filename)))
         (current-date (date-to-time date-string))
         (previous-date (time-subtract current-date (days-to-time 1)))
         (previous-filename (format-time-string "%Y_%m_%d.org" previous-date)))
    (if (file-exists-p previous-filename)
        (progn  (find-file previous-filename)
                (org-logseq-open-external-by-title))
      (message "The file for the previous day does not exist."))))

(defun org-logseq-switch-to-next-day ()
  "Switch to the next day's log file with format YYYY_MM_DD.org."
  (interactive)
  (let* ((current-filename (buffer-file-name))
         (date-string (replace-regexp-in-string "_" "-" (file-name-base current-filename)))
         (current-date (date-to-time date-string))
         (next-date (time-add current-date (days-to-time 1)))
         (next-filename (format-time-string "%Y_%m_%d.org" next-date)))
    (if (file-exists-p next-filename)
        (progn
          (find-file next-filename)
          (org-logseq-open-external-by-title)
          )
      (message "The file for the next day does not exist."))))


(defun org-logseq-activate ()
  "Override the default open behavior of org."
  (advice-add 'org-open-at-point :override #'org-logseq-open-at-point-inside)
  (advice-add 'org-open-at-mouse :override #'org-logseq-open-at-point-inside))

(defun org-logseq-deactivate ()
  "Restore the default open behavior of org."
  (advice-remove 'org-open-at-point #'org-logseq-open-at-point-inside)
  (advice-remove 'org-open-at-mouse #'org-logseq-open-at-point-inside))

(defvar org-logseq-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap org-open-at-point] 'org-logseq-open-at-point-inside)
    (define-key map [remap org-open-at-mouse] 'org-logseq-open-at-point-inside)
    map)
  "'org-logseq-mode' map.")

(define-minor-mode org-logseq-mode
  "Org-logseq minor mode."
  :init-value nil
  :global nil
  :keymap org-logseq-mode-map
  (cursor-sensor-mode t)
  )

(defun org-logseq-insert-clipboard-file-link ()
  (interactive)
  (let* ((clipboard-content (substring-no-properties (current-kill 0)))
         ;; 去除 "file://" 前缀并解码 URI
         (decoded-path (url-unhex-string (substring clipboard-content 7)))
         (destination-dir (concat org-logseq-dir "/assets/"))
         (filename (file-name-nondirectory decoded-path))
         ;; 生成时间戳后缀
         (time-suffix (format-time-string "_%Y_%m_%d_%H_%M_%S"))
         ;; 添加时间戳后缀到文件名
         (new-filename (concat (file-name-sans-extension filename) time-suffix (file-name-extension filename t)))
         (destination (concat destination-dir new-filename)))

    ;; 检查解码后的路径是否是一个存在的文件
    (when (file-exists-p decoded-path)
      ;; 复制文件到新位置
      (copy-file decoded-path destination)
      (delete-file decoded-path)

      ;; 计算相对路径并插入链接
      (let ((relative-path (file-relative-name destination (file-name-directory (buffer-file-name)))))
        (insert (format "[[file:%s][%s]]" relative-path filename))))))

(defun org-logseq-insert-and-move-file ()
  (interactive)
  (let* ((selected-file (read-file-name "Select file: "))
         (destination-dir (concat org-logseq-dir "/assets/"))
         (filename (file-name-nondirectory selected-file))
         ;; 生成时间戳后缀
         (time-suffix (format-time-string "_%Y_%m_%d_%H_%M_%S"))
         ;; 添加时间戳后缀到文件名
         (new-filename (concat (file-name-sans-extension filename) time-suffix (file-name-extension filename t)))
         (destination (concat destination-dir new-filename)))

    ;; 检查选择的文件是否存在
    (when (file-exists-p selected-file)
      ;; 复制文件到新位置
      (copy-file selected-file destination)
      (delete-file selected-file)

      ;; 计算相对路径并插入原始文件名的链接
      (let ((relative-path (file-relative-name destination (file-name-directory (buffer-file-name)))))
        (insert (format "[[file:%s][%s]]" relative-path filename))))))


(defun org-logseq-compact-region-and-replace-formula (start end)
  "Compact the region by removing extra lines, adding spaces, and replacing formula patterns, while preserving the final newline in the region."
  (interactive "r")
  (save-excursion
    ;; 删除选中区域内多余的空行
    (goto-char start)
    (while (re-search-forward "[ \t]*\n[ \t]*\n*" end t)
      (replace-match " " nil nil))
    (setq end (point-marker)) ; 更新end为marker，自动调整位置
    ;; 确保每行末尾有一个空格
    (goto-char start)
    (while (< (point) end)
      (end-of-line)
      (insert " ")
      (forward-line 1))
    ;; 查找并替换符合模式的字符串
    (goto-char start)
    (let ((pattern "\\( \\)\\\\(\\(.*?\\)\\\\)\\(.*?\\)\\( \\)")
          (replacement "\\1\\\\(\\2\\\\)\\4"))
      (while (re-search-forward pattern end t)
        (replace-match replacement nil nil)))
    (goto-char start)
    (while (re-search-forward " \\([.,]\\)" end t)
      (replace-match "\\1" nil nil))
    ;; 检查并确保选中区域末尾是一个换行符
    (goto-char end)
    (unless (or (= (point) (point-max))
                (string= "\n" (buffer-substring-no-properties end (1+ end))))
      (insert "\n"))))

;; (add-hook 'org-logseq-mode-hook
;;             #'(lambda ()
;;                 (add-hook 'after-save-hook 'org-logseq-make-block-ref-overlays nil 'make-it-local)))
;; (evil-define-key 'normal org-logseq-mode-map (kbd "zc") 'org-logseq-evil-close-fold)
;; (evil-define-key 'normal org-logseq-mode-map (kbd "zo") 'org-logseq-evil-open-fold)
(provide 'org-logseq)
;;; org-logseq.el ends here

;; SPDX-FileCopyrightText: 2026  Ben H.W.<foss@bhw.name>
;; SPDX-License-Identifier: MIT

(uiop:define-package #:org.sttimothyto/webserver
  ;; http://fare.tunes.org/files/asdf3/asdf3-2014.html#(part._.Package_.Upgrade)
  (:mix #:common-lisp #:alexandria #:serapeum)
  (:mix-reexport #:clog #:clog-web #:clog-auth #:clog-web-dbi)
  (:import-from #:ironclad)
  (:import-from #:usocket)
  (:import-from #:dbi)
  ;; DBI:CONNECT lazy-loads its driver system via ASDF at runtime, which
  ;; fails inside the deployed image (no source registry); depending on it
  ;; here bakes the sqlite driver into the build.
  (:import-from #:dbd.sqlite3)
  (:local-nicknames
   (#:conn      #:clog-connection))
  (:export :*server*
   :*sql-connection*
   #:initialize-application
   #:terminate-application
   #:application-toplevel)
  (:documentation "St. Timothy Parish (Toronto) website, hosted at
sttimothyto.org. Pages are built with CLOG-web's website framework
(CREATE-WEB-SITE / CREATE-WEB-PAGE) following CLOG tutorial 32:
announcements are stored in a sqlite database and edited in the browser
by signed-in parish staff."))

(in-package #:org.sttimothyto/webserver)

(defvar *server* nil
  "Non-NIL when the CLOG web server is running.")

(defvar *sql-connection* nil
  "cl-dbi sqlite handle for the users and content tables.")

;; Override CLOG-CONNECTION::RANDOM-HEX-STRING. Upstream's POSIX path uses
;; cl-isaac's RAND32, which unconditionally DECFs an (UNSIGNED-BYTE 32)
;; struct slot before checking for zero. With (SAFETY 2) from make.lisp, the
;; slot writer signals a TYPE-ERROR on the underflow, wedging the PRNG --
;; every subsequent call retraps, so CLOG can no longer mint connection IDs
;; and fresh browser sessions never receive the bootstrap frame. CLOG's own
;; Windows branch already uses ironclad; we extend that to all platforms.
(defun conn::random-hex-string ()
  "Generate a cryptographic 128-bit random hex string for connection IDs."
  (ironclad:byte-array-to-hex-string (ironclad:random-data 16)))

;;; Parish Content

(defparameter *mass-times*
  '("Sunday: 8:00 am, 10:00 am (livestreamed), 12:00 pm, 5:00 pm"
    "Saturday Vigil: 5:00 pm"
    "Weekday Mornings: Tuesday to Saturday 9:00 am"
    "Weekday Evenings: Monday to Friday 7:00 pm"))

(defparameter *confession-times*
  '("Wednesday: 9:45 to 10:30 am and 7:30 to 8:30 pm"
    "Friday: 7:30 to 8:30 pm"
    "Saturday: 4:30 to 4:55 pm"
    "Sunday: 30 minutes before each Mass"))

(defparameter *adoration-times*
  '("Tuesday to Thursday: 10:00 am to 6:30 pm"
    "Wednesday and Friday: 7:30 to 8:30 pm"))

(defparameter *footer-html*
  "<div class='w3-container w3-indigo w3-padding-32 w3-center'>
     <p><b>St. Timothy Parish</b><br>
     21 Leith Hill Road, North York, ON M2J 1Y9<br>
     Phone: 416.494.6526 &middot;
     <a class='w3-text-white' href='mailto:parish@sttimothyto.org'>parish@sttimothyto.org</a><br>
     Office Hours: Monday to Friday 9:00 am to 4:00 pm (closed 12:00 to 1:00 pm)</p>
     <p class='w3-small'>St. Timothy Parish is a registered charitable organization
     under the <i>Income Tax Act</i> (Canada).
     Charitable Registration Number 10791 0259 RR0001.</p>
   </div>"
  "Rendered by the theme at the bottom of every page. The second paragraph
is the Canada Revenue Agency charitable-status disclosure (registered
charity under the Income Tax Act (Canada), with the parish's business
number).")

(defparameter *about-html*
  "<div class='w3-container w3-padding-32' style='max-width:800px;margin:auto'>
     <h2>Welcome to St. Timothy's</h2>
     <p>Whether you are visiting for the first time or have worshipped here
        for years, we are glad you are with us. St. Timothy Parish is a Roman
        Catholic community in the Archdiocese of Toronto, serving the
        neighbourhoods around Don Mills Road and Sheppard Avenue East in
        North York.</p>
     <p>New to the parish? Please introduce yourself to one of the priests
        after Mass, or contact the parish office to register &mdash; we would
        love to welcome you.</p>
     <h3>Our Clergy</h3>
     <ul class='w3-ul'>
       <li>Rev. Brenton Cordeiro, CC &mdash; Pastor</li>
       <li>Rev. Karl Hartman, CC &mdash; Associate Pastor</li>
       <li>Rev. Kenneth Lao, CC &mdash; Associate Pastor</li>
       <li>Deacon Francis Vaz &mdash; Deacon Assistant</li>
     </ul>
   </div>")

(defparameter *contact-html*
  "<div class='w3-container w3-padding-32' style='max-width:800px;margin:auto'>
     <h2>Contact Us</h2>
     <p><b>St. Timothy Parish</b><br>
        21 Leith Hill Road<br>
        North York, ON M2J 1Y9<br>
        <a href='https://maps.google.com/?q=21+Leith+Hill+Road,+North+York,+ON+M2J+1Y9'
           target='_blank'>Map and directions</a></p>
     <p>Phone: 416.494.6526<br>
        Email: <a href='mailto:parish@sttimothyto.org'>parish@sttimothyto.org</a></p>
     <h3>Office Hours</h3>
     <p>Monday to Friday: 9:00 am to 4:00 pm (closed 12:00 to 1:00 pm)</p>
   </div>")

;;; Menu
;;;
;;; Item shape: (\"Label\" \"url\" [handler [auth-action]]).
;;; CLOG-WEB-ROUTES-FROM-MENU registers a route for each item that names a
;;; handler; DEFAULT-THEME hides items whose auth-action the current roles
;;; lack and destroys drop-downs left empty (the Account menu for guests).

(defparameter *menu*
  `(("Parish"  (("Home"              "/")
                ("About Us"          "/about"    on-about)
                ("Contact"           "/contact"  on-contact)))
    ("Worship" (("Mass & Sacraments" "/schedule" on-schedule)
                ("Announcements"     "/news"     on-news)))
    ("Account" (("Change Password"   "/pass"     on-new-pass :change-password)
                ("Manage Users"      "/users"    on-users    :users)
                ("Logout"            "/logout"   on-logout   :logout))))
  "Site menu.")

;;; Site Chrome

(defparameter *site-style*
  "<style>
:root{
  /* Cinzel-lookalike engraved-Roman display serif -- the parish wordmark
     font, shared by the header title, the hero and (on the landing page)
     the headings. 'Cinzel' when the browser has it, otherwise the nearest
     widely available engraved-Roman serifs. */
  --stt-display:'Cinzel','Trajan Pro','Optima','Palatino Linotype','Book Antiqua',Palatino,Georgia,'Times New Roman',serif;
}

/* Warm parchment page background instead of stark white; the parish
   photos, indigo chrome and white cards all sit on top of it. */
body{background-color:#f2e8d3;}

/* Center the parish name and render it in the display serif. The theme
   header row (w3-cell-row, a CSS table) is an empty logo cell followed by
   the title cell; with no logo the first cell is dead weight, so drop it
   -- the title cell then spans the full-width row -- then center it and
   swap the theme's w3-sans-serif for the parish wordmark font so the
   header name matches the hero and headings. */
.w3-cell-row > .w3-cell:first-child{display:none;}
.w3-cell-row{text-align:center;}
.w3-cell-row .w3-sans-serif{font-family:var(--stt-display);}

/* Center the navigation menu and set its top-level labels (Parish,
   Worship, Account) in the parish display serif. Inside a w3-bar the
   drop-downs are float:left (w3.css), which text-align can't move, so
   switch them to inline-block and center them. The label is the button
   that is a direct child of the drop-down; the > combinator spares the
   nested drop-down items. The login link keeps its w3-right float and
   stays in the corner; drop-down items stay left-aligned. */
.w3-bar .w3-dropdown-hover{float:none;display:inline-block;vertical-align:middle;}
.w3-bar .w3-dropdown-hover > .w3-button{font-family:var(--stt-display);}
.w3-bar{text-align:center;}
.w3-bar .w3-dropdown-content{text-align:left;}
</style>"
  "Global stylesheet injected into every page <head> by INIT-SITE. Defines
the parish display serif (--stt-display), centers the header title and
nav menu, and dresses the title in that display serif.")

(defun compute-roles (profile)
  "Site roles for PROFILE. There is no public signup -- accounts are
created by the admin on /users -- so every signed-in user is an editor."
  (cond ((null profile) '(:guest))
        ((equalp "admin" (getf profile :|username|)) '(:member :editor :admin))
        (t '(:member :editor))))

(defun init-site (body)
  "Per-connection site setup. Called at the top of every URL handler."
  (clog-web-initialize body)
  (setf (title (html-document body)) "St. Timothy Parish | Toronto")
  (create-child (head-element (html-document body)) *site-style*)
  ;; Reload open windows when the user logs in or out in another tab.
  (set-on-authentication-change body (lambda (body)
                                       (url-replace (location body) "/")))
  (let ((profile (get-profile body *sql-connection*)))
    (create-web-site body
                     :settings '(:color-class  "w3-indigo"
                                 :border-class ""
                                 :login-link   "/login")
                     :profile profile
                     :roles   (compute-roles profile)
                     :title   "St. Timothy Parish"
                     :footer  *footer-html*
                     ;; NIL, not the default "": the theme renders any
                     ;; non-NIL logo as an <img>.
                     :logo    nil)))

;;; Landing Page Sections

(defparameter *photo-types* '("jpg" "jpeg" "png" "webp" "gif" "avif")
  "Image extensions recognised in photos/ for the parallax slideshow.")

(defun photo-number (filename)
  "Leading integer of FILENAME (\"10.jpeg\" -> 10), or 0 when it has none,
so the slideshow runs 1,2,...,11 rather than lexical 1,10,11,2."
  (or (ignore-errors (parse-integer (pathname-name (pathname filename))))
      0))

(defparameter *parallax-photos*
  (sort (mapcar #'file-namestring
                (remove-if-not (lambda (p)
                                 (member (pathname-type p) *photo-types*
                                         :test #'string-equal))
                               (uiop:directory-files
                                (asdf:system-relative-pathname
                                 :org.sttimothyto "photos/"))))
        #'< :key #'photo-number)
  "Every image in photos/ (served under /photos/), numerically sorted.
The landing-page parallax bands crossfade through this whole list.")

(defparameter *slide-seconds* 6
  "Seconds each parallax photo is held before crossfading to the next.")

(defparameter *fade-seconds* 1.5
  "Duration of each parallax crossfade, in seconds.")

(defparameter *landing-style*
  "<style>
/* --stt-display, the parish display serif, is defined globally in
   *SITE-STYLE*; here it dresses the landing-page headings and captions. */
.stt-display,
h1,h2,h3,.w3-jumbo,.stt-parallax-caption{font-family:var(--stt-display);}
h1,h2,.w3-jumbo{text-transform:uppercase;letter-spacing:.08em;font-weight:600;}
h3{letter-spacing:.04em;}

/* Pure-CSS parallax bands, each a crossfading slideshow. Every photo is
   an absolutely-positioned .stt-slide layer (z-index 0); the indigo
   overlay sits above the photos (z-index 1) and the caption above that
   (z-index 2). The indigo base shows before the first fade-in.
   isolation:isolate confines those layers to the band's own stacking
   context -- otherwise the caption/overlay leak into the page stacking
   context and paint over the menu's drop-downs where they overlap. */
.stt-parallax{
  position:relative;
  isolation:isolate;
  background-color:#1a237e;
  display:flex;
  align-items:center;
  justify-content:center;
  text-align:center;
}
.stt-parallax::before{content:'';position:absolute;inset:0;z-index:1;background:rgba(26,35,126,.45);}
.stt-hero{min-height:88vh;}

/* One crossfading photo. The per-layer background-image and
   animation-delay are set inline; the shared animation and @keyframes
   (sized to the photo count) come from SLIDESHOW-STYLE. */
.stt-slide{
  position:absolute;inset:0;z-index:0;
  background-position:center center;
  background-repeat:no-repeat;
  background-size:cover;
  background-attachment:fixed;
  opacity:0;
  will-change:opacity;
}
.stt-parallax-caption{
  position:relative;z-index:2;
  color:#fff;max-width:900px;padding:0 1.2rem;
  text-shadow:0 2px 14px rgba(0,0,0,.65);
}
.stt-parallax-caption a{text-shadow:none;}

/* background-attachment:fixed is janky / unsupported on mobile Safari;
   fall back to a static cover image there, keeping the photograph. */
@media (max-width:768px){
  .stt-slide{background-attachment:scroll;}
  .stt-hero{min-height:70vh;}
}
</style>"
  "Inline stylesheet injected into the landing page <head>: applies the
parish display serif (defined in *SITE-STYLE*) to the headings and styles
the CSS parallax bands. Scoped to the landing page by being emitted only
from ON-HOME.")

(defun slideshow-style ()
  "A <style> block sized to the number of *PARALLAX-PHOTOS*: the shared
.stt-slide animation and the crossfade @keyframes, whose percentages
depend on the photo count. Injected into the landing-page <head>.

Each slide is fully shown for its SLOT of the cycle, then dissolves over
FADE% into the next; with the staggered ANIMATION-DELAYs one slide's
fade-out lines up with the next's fade-in, so the two truly crossfade."
  (let* ((n     (length *parallax-photos*))
         (total (* n *slide-seconds*))
         (slot  (/ 100.0 n))
         (fade  (/ (* *fade-seconds* 100.0) total)))
    (format nil "<style>
.stt-slide{animation:stt-slideshow ~,2Fs linear infinite;}
@keyframes stt-slideshow{
  0%{opacity:0}
  ~,3F%{opacity:1}
  ~,3F%{opacity:1}
  ~,3F%{opacity:0}
  100%{opacity:0}
}
</style>"
            total fade slot (+ slot fade))))

(defun create-slideshow (band)
  "Fill parallax BAND with one crossfading .stt-slide layer per photo in
*PARALLAX-PHOTOS*, cycling through every parish photograph. Each layer is
a viewport-fixed cover background; the staggered ANIMATION-DELAYs -- one
slide-length apart, warm-started by FADE-SECONDS so the first photo is
already on screen at load -- dissolve one into the next."
  (loop for photo in *parallax-photos*
        for i from 0
        do (create-div band
                       :class "stt-slide"
                       ;; NB: no quotes inside url() -- CLOG wraps the
                       ;; style attribute value in single quotes, so an
                       ;; inner ' would truncate the declaration.
                       :style (format nil "background-image:url(/photos/~A);animation-delay:~,2Fs"
                                      photo (- (* i *slide-seconds*) *fade-seconds*)))))

(defun create-parallax (parent &key caption subcaption (min-height "70vh"))
  "Full-bleed CSS parallax band: a crossfading slideshow of the parish
photographs as fixed-attachment cover backgrounds, dimmed by an indigo
overlay, with an optional centered CAPTION/SUBCAPTION in the display
font."
  (let ((band (create-div parent
                          :class "stt-parallax"
                          :style (format nil "min-height:~A" min-height))))
    (create-slideshow band)
    (when (or caption subcaption)
      (let ((cap (create-div band :class "stt-parallax-caption")))
        (when caption
          (create-section cap :h2 :content caption :class "w3-xxlarge"))
        (when subcaption
          (create-p cap :content subcaption :class "w3-large"))))
    band))

(defun create-hero (parent)
  "Full-bleed parallax banner: a crossfading slideshow of parish
photographs behind the parish name, tagline and I'm New? call to action."
  (let ((hero (create-div parent :class "stt-parallax stt-hero")))
    (create-slideshow hero)
    (let ((cap (create-div hero :class "stt-parallax-caption")))
      (create-section cap :h1 :content "St. Timothy Parish" :class "w3-jumbo")
      (create-p cap
                :content "A Roman Catholic parish in the Archdiocese of Toronto"
                :class "w3-xlarge")
      (create-a cap :content "I'm New?" :link "/about"
                    :class "w3-button w3-white w3-round-large w3-large w3-margin-top"))))

(defun create-welcome (parent)
  (let ((sec (create-web-container parent :class "w3-padding-32 w3-center")))
    (create-section sec :h2 :content "Welcome")
    (create-p sec :content
              "Join us for Mass, confession and Eucharistic adoration at
21 Leith Hill Road in North York, near Don Mills and Sheppard.")))

(defun create-info-card (row title times)
  (let ((card (create-web-container row :column-size :third
                                        :class "w3-white w3-padding-16")))
    (add-card-look card)
    (create-section card :h3 :content title :class "w3-text-indigo w3-center")
    (let ((ul (create-unordered-list card :class "w3-ul")))
      (dolist (time times)
        (create-list-item ul :content time)))))

(defun create-schedule-cards (parent)
  "Three cards: mass, confession and adoration times. Shared by the
landing page and /schedule."
  (let ((row (create-web-row parent :padding t)))
    (create-info-card row "Mass Times" *mass-times*)
    (create-info-card row "Confession" *confession-times*)
    (create-info-card row "Eucharistic Adoration" *adoration-times*)))

(defun create-announcements (parent)
  "Database-backed announcements. Signed-in users get the theme's inline
add/edit/delete controls."
  (let ((sec (create-web-container parent)))
    (create-section sec :h2 :content "Announcements" :class "w3-center")
    (funcall (clog-web-content *sql-connection*
                               :page "announcements"
                               :base-url "/news"
                               ;; Pin the page key: the landing page URL is
                               ;; "/", not under /news.
                               :follow-url-page nil)
             sec)))

;;; URL Handlers

(defun on-home (body)
  (init-site body)
  (create-web-page body :index
                   `(:menu ,*menu*
                     :content ,(lambda (parent)
                                 (let ((head (head-element (html-document parent))))
                                   (create-child head *landing-style*)
                                   (create-child head (slideshow-style)))
                                 (create-hero parent)
                                 (create-welcome parent)
                                 (create-parallax parent
                                                  :caption "Come and Worship"
                                                  :subcaption "The Holy Sacrifice of the Mass, at the heart of parish life")
                                 (create-schedule-cards parent)
                                 (create-parallax parent
                                                  :caption "A Parish Family"
                                                  :subcaption "Walking together in faith in the Archdiocese of Toronto")
                                 (create-announcements parent)))))

(defun on-about (body)
  (init-site body)
  (create-web-page body :about `(:menu ,*menu* :content ,*about-html*)))

(defun on-contact (body)
  (init-site body)
  (create-web-page body :contact `(:menu ,*menu* :content ,*contact-html*)))

(defun on-schedule (body)
  (init-site body)
  (create-web-page body :schedule
                   `(:menu ,*menu*
                     :content ,(lambda (parent)
                                 (create-section parent :h2
                                                 :content "Mass & Sacraments"
                                                 :class "w3-center")
                                 (create-schedule-cards parent)
                                 (create-p parent
                                           :content "Times may change for weddings or
funerals. Please check the bulletin or call the parish office to confirm."
                                           :class "w3-center")))))

(defun on-news (body)
  "Announcements archive and CMS. :EXTENDED-ROUTING sends /news/* here,
so editors can create sub-pages (e.g. /news/lent) from the browser."
  (init-site body)
  (create-web-page body :news
                   `(:menu ,*menu*
                     :content ,(lambda (parent)
                                 (create-section parent :h2
                                                 :content "Announcements"
                                                 :class "w3-center")
                                 (funcall (clog-web-content *sql-connection*
                                                            :page "announcements"
                                                            :base-url "/news")
                                          parent)))))

(defun create-login-form (parent on-submit)
  "Username/password form styled like DEFAULT-THEME's :login page, minus
its hardwired sign-up link (this site has no public signup)."
  (let* ((outter (create-web-container parent))
         (form   (create-form outter))
         (p1     (create-p form))
         (user   (progn (create-label p1 :content "User Name")
                        (create-form-element p1 :text :name "username"
                                                      :class "w3-input")))
         (p2     (create-p form))
         (pass   (progn (create-label p2 :content "Password")
                        (create-form-element p2 :password :name "password"
                                                          :class "w3-input"))))
    (setf (maximum-width outter) (unit :px 500))
    (setf (requiredp user) t)
    (setf (requiredp pass) t)
    (create-form-element form :submit :value "Sign In"
                                      :class "w3-button w3-indigo")
    (set-on-submit form on-submit)))

(defun on-login (body)
  (init-site body)
  ;; Custom :sign-in page keyword instead of the theme's :login branch --
  ;; see CREATE-LOGIN-FORM. :AUTHORIZE uses the page keyword as the
  ;; clog-auth action, so :sign-in is granted to :guest.
  (create-web-page body :sign-in
                   `(:menu ,*menu*
                     :content ,(lambda (parent)
                                 (create-login-form
                                  parent
                                  (lambda (obj)
                                    (if (login body *sql-connection*
                                               (name-value obj "username")
                                               (name-value obj "password"))
                                        (url-replace (location body) "/")
                                        (clog-web-alert obj "Invalid"
                                                        "The username or password is incorrect."
                                                        :time-out 3
                                                        :place-top t))))))
                   :authorize t))

(defun on-logout (body)
  (logout body)
  (url-replace (location body) "/"))

(defun on-new-pass (body)
  (init-site body)
  (create-web-page body :change-password
                   `(:menu ,*menu*
                     :content ,(lambda (parent)
                                 (change-password parent *sql-connection*)))
                   :authorize t))

(defun on-users (body)
  "Admin page: reset passwords and add users. Replaces public signup."
  (init-site body)
  (create-web-page body :users
                   `(:menu ,*menu*
                     :content ,(lambda (parent)
                                 (create-section parent :h3 :content "Parish Users")
                                 (let ((users (dbi:fetch-all
                                               (dbi:execute
                                                (dbi:prepare
                                                 *sql-connection*
                                                 "select * from users")))))
                                   (dolist (user users)
                                     (let* ((box  (create-div parent))
                                            (rbut (progn
                                                    (create-span box :content (getf user :|username|))
                                                    (create-button box :content "Reset Password"
                                                                       :class "w3-margin-left"))))
                                       (set-on-click rbut
                                                     (lambda (obj)
                                                       (declare (ignore obj))
                                                       (reset-password *sql-connection*
                                                                       (getf user :|username|))
                                                       (setf (disabledp rbut) t)
                                                       (setf (text rbut) "Done"))))))
                                 (sign-up parent *sql-connection*
                                          :title "Add Parish User"
                                          :next-step "/users")))
                   :authorize t))

(defun on-404 (body)
  "Styled 404 for boot-served paths that have no handler."
  (init-site body)
  (create-web-page body :404
                   `(:menu ,*menu*
                     :content "<h1>Page not found</h1>
<p>Try the menu above, or return <a href='/'>home</a>.</p>")))

;;; Database and Authorization

(defun initialize-database ()
  "Open (creating and seeding on first run) the parish sqlite database."
  (when *sql-connection*
    (ignore-errors (dbi:disconnect *sql-connection*)))
  (let ((db-path (namestring (asdf:system-relative-pathname
                              :org.sttimothyto "sttimothyto.db"))))
    (setf *sql-connection* (dbi:connect :sqlite3 :database-name db-path))
    (format t "Database location: ~A~%" db-path))
  (handler-case
      (dbi:fetch (dbi:execute (dbi:prepare *sql-connection* "select * from config")))
    (error ()
      (format t "First run: creating base tables and seed content.~%")
      ;; Seeds the users table with admin/admin -- change that password!
      (create-base-tables *sql-connection*)
      ;; CREATE-BASE-TABLES also seeds a sample row keyed \"main\" that
      ;; this site never displays.
      (dbi:do-sql *sql-connection* "delete from content where key='main'")
      (dbi:do-sql *sql-connection*
        (sql-insert* "content"
                     `(:key        "announcements"
                       :title      "Welcome to our new parish website"
                       :value      "Watch this space for parish news and announcements."
                       :createdate (,*sqlite-timestamp*)))))))

(defun disconnect-database ()
  (when *sql-connection*
    (ignore-errors (dbi:disconnect *sql-connection*))
    (setf *sql-connection* nil)))

(defun initialize-authorizations ()
  "Register role -> action grants. Idempotent: ADD-AUTHORIZATION adjoins."
  (add-authorization '(:guest)  '(:sign-in))
  (add-authorization '(:member) '(:logout :change-password))
  (add-authorization '(:editor) '(:content-edit))
  (add-authorization '(:admin)  '(:users :content-admin)))

;;; Server Lifecycle

(defun wait-for-port-ready (port &key (host "127.0.0.1") (timeout 5.0) (interval 0.05))
  "Block until something is accepting TCP connections on HOST:PORT, or
TIMEOUT seconds elapse. Returns T on success, NIL on timeout. CLOG's
INITIALIZE returns as soon as clack:clackup hands back a handler struct,
but the underlying hunchentoot acceptor finishes START in a separate
thread. If TERMINATE-APPLICATION runs before that thread has populated
HUNCHENTOOT::ACCEPTOR-PROCESS, clack's BT2:DESTROY-THREAD cleanup hits
UNBOUND-SLOT and crashes the handler thread. Polling here closes that
window."
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (loop
      (handler-case
          (let ((sock (usocket:socket-connect host port)))
            (usocket:socket-close sock)
            (return t))
        (error ()
          (when (> (get-internal-real-time) deadline)
            (return nil))
          (sleep interval))))))

(defun terminate-application (&optional sigint-poll)
  "Stop the web server started by `initialize-application', if it exists. When
called with a non NIL value for SIGINT-POLL, it will listen for SIGINT (Catch a
user's Control-c in the terminal) and gracefully shut down the web server and
exit the lisp process."
  (when sigint-poll
    (handler-case (loop (sleep 1))
      (#+sbcl sb-sys:interactive-interrupt
       #+ccl  ccl:interrupt-signal-condition
       #+clisp system::simple-interrupt-condition
       #+ecl ext:interactive-interrupt
       #+allegro excl:interrupt-signal
       () (progn
            (format *error-output* "~%Aborting.~&~%")
            (when (find-package :slynk)
              (funcall (intern "STOP-SERVER" :slynk) 4005))
            (disconnect-database)
            (shutdown)
            (format t "~%Server successfully stopped.~%")
            (uiop:quit)))
      (error (c) (format t "Whoops, an unknown error occured:~&~a~&" c))))
  (when (or *server* (is-running-p))
    (ignore-errors
     (progn
       (disconnect-database)
       (shutdown)
       (setf *server* nil)
       (format t "~%Server successfully stopped.~%")
       (return-from terminate-application t)))))

(defun initialize-application (&key (port 8080))
  "Start a CLOG web server at PORT serving the St. Timothy Parish website.

Slynk server is used to connect to a running production LISP image.

See APPLICATION-TOPLEVEL for the main function or entry point."
  (terminate-application)
  (initialize-authorizations)
  (initialize-database)
  ;; Default :static-root -- CLOG's own static-files/ -- serves /css/w3.css,
  ;; /js/boot.js, /boot.html (with the cl-template markers CLOG-WEB-META
  ;; needs) and /favicon.ico.
  (initialize 'on-home
              :host "127.0.0.1"
              :port port
              :extended-routing t
              :long-poll-first t
              :boot-function (clog-web-meta
                              "St. Timothy Parish, a Roman Catholic parish in the
Archdiocese of Toronto. Mass times, confession, adoration and parish
announcements. 21 Leith Hill Road, North York."))
  ;; /about /contact /schedule /news /pass /users /logout
  (clog-web-routes-from-menu *menu*)
  ;; Not in the menu; the theme's right-corner login link targets it.
  (set-on-new-window 'on-login :path "/login")
  (set-on-new-window 'on-404 :path :default)
  ;; Project static assets (images etc.) served under /assets/.
  (conn:add-plugin-path "^/assets/"
                        (namestring (asdf:system-relative-pathname :org.sttimothyto "./")))
  ;; Parish photographs for the landing-page parallax, served under /photos/.
  (conn:add-plugin-path "^/photos/"
                        (namestring (asdf:system-relative-pathname :org.sttimothyto "./")))
  (setf *server* t)
  (format t "~%
========================================
St. Timothy Parish Website v0.1.0 (CLOG-web)
========================================

Copyright (c) 2026  Ben H. W. <foss@bhw.name>

On first run the database is seeded with user 'admin', password 'admin'.
Sign in at http://localhost:~A/login and change it at /pass immediately.

Navigate to http://localhost:~A to continue... ~%" port port)
  (wait-for-port-ready port)
  (return-from initialize-application t))

(defun application-toplevel ()
  "Application entry point. Emulate a \"main\" function. Used in
  SAVE-LISP-AND-DIE to save Application as a Lisp image. Note PORT is a keyword
  argument that defaults to 8080. Heroku dynamically sets the PORT variable to
  be binded."
  (let* ((port (if (equalp NIL (uiop:getenv "PORT"))
                   8080
                   (parse-integer (uiop:getenv "PORT")))))
    ;; We only want one connection to a remote lisp.
    (when (= 8080 port)
      (progn
        (when (find-package :slynk)
          (funcall (intern "CREATE-SERVER" :slynk) :port 4005 :dont-close t)
          (setf (symbol-value (intern "*USE-DEDICATED-OUTPUT-STREAM*" :slynk)) nil))))
    (initialize-application :port port)
    (format t "~% Close this window or press Control+C to exit the program...~%")
    (terminate-application t)))

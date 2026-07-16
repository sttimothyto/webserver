;;;; SPDX-FileCopyrightText: 2026  Ben H. W. <foss@bhw.name>
;;;; SPDX-License-Identifier: MIT
(in-package :cl-user)

(consfigurator:defpackage-consfig :org.sttimothyto/infra
    (:use #:common-lisp #:consfigurator)
  (:export #:sttimothyto-prod))

(in-package :org.sttimothyto/infra)
(in-consfig "org.sttimothyto/infra")
(named-readtables:in-readtable :consfigurator)

(defhost sttimothyto-prod (:deploy :ssh)
  "Declarative Configuration for Production Server. To deploy to production run
locally in the listener,

CL-USER> (asdf:load-system \"org.sttimothyto/infra\")
CL-USER> (org.sttimothyto/infra:sttimothyto-prod)

NOTE that if (asdf:load-system \"consfigurator\") fails with CFFI unable to find
C libraries, locally apt install packages listed in
`consfigurator.property.package:+consfigurator-system-dependencies+'.

One piece of information is unique to this host: remote root SSH login access on
the local machine in ~/.ssh/config, under the Host alias sttimothyto-prod --
consfigurator connects to the DEFHOST symbol name as the ssh hostname.

Caddy (TLS termination + reverse proxy to http://127.0.0.1:8080) and DNS are
managed manually on the host, outside this consfig."
  (os:debian-stable "trixie" :amd64)
  (timezone:configured "America/Toronto")
  ;; Fresh Hetzner image ships a stale apt cache; refresh before installing.
  (apt:updated)
  (apt:installed "firewalld")
  (systemd:enabled "firewalld")
  (systemd:started "firewalld")
  ;; HTTP is needed alongside HTTPS for ACME challenges once Caddy is set up.
  (cmd:single "firewall-cmd --permanent --add-service=http")
  (cmd:single "firewall-cmd --permanent --add-service=https")
  (cmd:single "firewall-cmd --reload")
  (systemd:restarted "firewalld")
  (apt:installed "sbcl" "sbcl-source" "git" "ocicl")
  ;; 2 GB RAM host: SBCL compiling ironclad/clog at (speed 3) can OOM
  ;; without swap. Not persisted to /etc/fstab; only the build needs it.
  (cmd:single "test -f /swapfile || (fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile)")
  (git:pulled "https://github.com/sttimothyto/webserver.git"
              (pathname "/usr/local/src/org.sttimothyto/"))
  (cmd:single "ocicl setup")
  ;; Dependency pinning lives in ocicl.csv at the project root, brought in by
  ;; the git:pulled step above. make.lisp loads ocicl-runtime; ocicl auto-fetches
  ;; any system listed in ocicl.csv that's missing from the local ocicl/ dir on
  ;; the first asdf:load-system call.
  (cmd:single (concatenate 'string
                           "cd /usr/local/src/org.sttimothyto/ && "
                           "sbcl "
                           ;; KLUDGE "--control-stack-size='4Mb' breaks."
                           "--control-stack-size '16Mb' "
                           "--dynamic-space-size '4Gb' "
                           ;; NOTE Use --script and not --load.
                           ;; http://www.sbcl.org/manual/#Toplevel-Options
                           "--script '/usr/local/src/org.sttimothyto/make.lisp'"))
  (cmd:single "install -m 755 /usr/local/src/org.sttimothyto/bin/sttimothyto /usr/local/bin/sttimothyto")
  ;; https://systemd-by-example.com/
  (file:has-content
   "/etc/systemd/system/sttimothyto.service"
   "
[Unit]
Description=St. Timothy Parish web application.
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/src/org.sttimothyto/
ExecStart=/usr/local/bin/sttimothyto
Restart=always

[Install]
WantedBy=multi-user.target")
  (systemd:daemon-reloaded)
  (systemd:enabled "sttimothyto.service")
  (systemd:restarted "sttimothyto.service"))

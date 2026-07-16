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
  ;; ocicl is not in Debian's archive; it ships from the ocicl project's own
  ;; apt repository (https://ocicl.github.io/ocicl/). Install its signing key
  ;; and source entry; APT:ADDITIONAL-SOURCES re-runs apt-get update on change.
  (file:has-content
   "/etc/apt/keyrings/ocicl-archive-keyring.asc"
   "-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGnbj5QBEADVomhvD25nd7f6G6g0P4uRDMzx4nDy6lAc/B1OJj28+vxrh9Z2
najUtlCr2DV+nvpbM0xNd1meG/gV878/pgIpN3tG2r3t/N8+LZZ0d8iKkIPF8wYA
tgoEUdn/sY7drkmIyolqoLrCUWOPBxfNR2+jrXHIal6MSxngc8UbiVAipCfzBP+w
trb4oOeZwpi+BsyMRz9c4Z4KjO6gHvpnHj/HhQhZJ1U3QsAQ1o6LI++kjpEnlkw5
L9s6Tfkj4kvH6RiBCN0AAez2/oOsRnkJ+opIrdY/wBAj4PJOnPmCASadc+LoL4C4
5NT4RufKI1mm7ZxabTK+muErRUwv8ueVAPo9VKqnfEEhLmRzmy7KD1pe0jpgEZBP
yrIbi0DrQH0FocySOpEpuyOTrhPUBVFA3tkz/LOyxEFLu1TrAknbpUUtGricWfLw
gpPGOqyIPjUZX8UYxk+bSyXE0L5J9dmx7Tp7P6PhiAHyWt5NIDqHe0AYL1H7rEPy
g/mpPENkU1Rk/cy8ly36geJud3AxzUtq/AP0THazlyrBP2YvOfMXKTNloYMAYyho
0Ez7ydPA1FnCO1swCU2mnQRIZWSlQ9bOuDQUoJdz38itCn45b7iJ7SeotVGEglqf
I5gXSuZQ1txq3lkvf9Duu5YKtawbyZpYV7tc11ch+N8KVkUK7PA+xQ+jfwARAQAB
tCxvY2ljbCBSUE0gU2lnbmluZyBLZXkgPGdyZWVuQG1veGllbG9naWMuY29tPokC
bgQTAQgAWBYhBJM46+jZ/v9dzO+V5IhvRs/urOmIBQJp24+UGxSAAAAAAAQADm1h
bnUyLDIuNSsxLjEyLDAsMgMbLwQFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcCF4AA
CgkQiG9Gz+6s6YgL/w//XXhtXhMec7LBdPnslrWcpGLt0aus+nBEsuAqg5e2CFB6
Yb2MnQ0Yb+3e4xRk9CJT5aVqugJwBtmwC6UNxg3JjwnIOSh7xw8W/C5vss9907bi
dw/yH3vmrmcYiPUuafKut1vvFqxNozCWZ+9fV/X+kOCqSI+4QHR9KaMcUeaEZ+Fj
6rkVBaF4+R0RdsHc0nxeKQ3Ci1yBbcASKsOM5yOaIJHn7Q/gVgfcZHRpEmWh67bG
so/Y/S2gQosEZybDZQjYxFAdwnIqiDiC4tc5F60ghN99iaP3c7lGgXQyU9Lehdvk
jPLUohQ+18OH6+fBWFrg5mqdDdhYJXB5U0v3ixhTMF6t7OwdYLVpW5cfGtVQmU7m
OsmHeSHEiJBSu7Wb6bHx3ftaHyWDFywSUIxklrsinz7Th3cJ5LX8S2M5BXyA5jlM
j5+LQKmZxApD4vcvXFC7P3DFgAxF0mOK6IArWH3pW1ZsprS4UU7AtoI/SF6OGd6z
H4bZcAUTIKS+1MqtNe8bRQZHC+udoEW6mF37B4AULKeA77s1K0VbFYRhc7H5t1rS
l8Rrhk24UsJpSEmGq/Gu37LzE6qrHn72y3lJJCqiJswKZaGrnkbx11DsBaWr+DC1
lT+S1Iwm0oFqkFU0IxDx2RAQy2EBL3uKETr9tmxT7gps3KXpAjQay1uzGGWgdZs=
=xcBL
-----END PGP PUBLIC KEY BLOCK-----")
  (apt:additional-sources "ocicl"
    "deb [signed-by=/etc/apt/keyrings/ocicl-archive-keyring.asc] https://ocicl.github.io/ocicl/deb-repo stable main")
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
  ;; A unit left crashlooping by an earlier failed deploy hits its start
  ;; limit; restart alone won't clear that state.
  (cmd:single "systemctl reset-failed sttimothyto.service || true")
  (systemd:restarted "sttimothyto.service"))

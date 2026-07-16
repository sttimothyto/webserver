;;;; sttimothyto-website.asd
;;;; SPDX-FileCopyrightText: 2026  Ben H. W. <foss@bhw.name>
;;;; SPDX-License-Identifier: MIT

#-asdf3.3 (error "Project Isidore requires ASDF 3.3 or later. Please upgrade your ASDF. See commit bf210b8.")

(asdf:defsystem "org.sttimothyto"
  :name "St Timothy Toronto Website"
  :version "0.1.0"
  :author "Ben H. W.<foss@bhw.name>"
  :maintainer "Ben H. W.<foss@bhw.name>"
  :description "St Timothy Parish Website hosted at sttimothyto.org"
  :license  "MIT"
  :homepage "tbd"
  :bug-tracker "tbd"
  :source-control (:git "tdb")
  :class :package-inferred-system
  :pathname "src"
  :depends-on ("org.sttimothyto/webserver")
  :in-order-to ((asdf:test-op (asdf:test-op "org.sttimothyto/tests")))
  :build-operation "program-op"
  :build-pathname "../bin/sttimothyto"
  :entry-point "org.sttimothyto/webserver:application-toplevel")

(register-system-packages "clog" '(:clog-connection :clog-web :clog-auth :clog-web-dbi))

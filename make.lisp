;;;; SPDX-FileCopyrightText: 2026  Ben H. W. <foss@bhw.name>
;;;; SPDX-License-Identifier: MIT

;; Load this file inside a shell to build a standalone executable binary,

;; "$ sbcl --dynamic-space-size '4Gb' --control-stack-size '16Mb'
;; --script /path/to/this/file.lisp"

(in-package #:cl-user)

;; See weitzCommonLispRecipes2016, page 102.
(setf *read-default-float-format* 'double-float)

;;; I. ASDF & OCICL CONFIGURATION
;; This file is loaded with `sbcl --script`, which skips .sbclrc, so configure
;; ASDF + ocicl explicitly here.
;;
;; org.sttimothyto and its dependencies are vendored locally via ocicl
;; (ocicl.csv + ocicl/). For a clean, deterministic build, pin
;; CL_SOURCE_REGISTRY to this project's directory *before* (require "asdf"):
;; otherwise ASDF's built-in default scans ~/common-lisp/ recursively and,
;; finding duplicate .asd files vendored by sibling ocicl projects, warns on
;; every build (and may pick their copies). org.sttimothyto.asd is found via
;; this single non-recursive entry; third-party deps resolve through ocicl's
;; searcher (loaded below).
(defvar *project-dir*
  (make-pathname :defaults (truename (or *load-pathname* *default-pathname-defaults*))
                 :name nil :type nil :version nil))
(require :sb-posix)
(sb-posix:setenv "CL_SOURCE_REGISTRY" (namestring *project-dir*) 1)

(require "asdf") ; load Utilities for Implementation- and OS-Portability.

(format t "~%~&        ====== MAKE.LISP ======~%")
;; NB: webserver.lisp's CONN::RANDOM-HEX-STRING override documents its
;; dependence on this (safety 2).
(declaim (optimize (safety 2) (speed 3) (space 0) (debug 0) (compilation-speed 0)))

;; Ensure ~/.local/bin is on PATH: ocicl-runtime spawns the `ocicl` binary to
;; install missing systems, and non-interactive shells (ssh, systemd) do not
;; inherit ~/.local/bin from .profile / .bashrc.
(let* ((home (uiop:getenv "HOME"))
       (local-bin (and home (concatenate 'string home "/.local/bin")))
       (path (or (uiop:getenv "PATH") "")))
  (when (and local-bin
             (probe-file (concatenate 'string local-bin "/ocicl"))
             (not (search local-bin path)))
    (setf (uiop:getenv "PATH") (concatenate 'string local-bin ":" path))))

;; ocicl resolves local systems by walking up from the current working
;; directory for ocicl.csv, so build from this project's directory regardless
;; of where the script was invoked.
(uiop:chdir *project-dir*)
(setf *default-pathname-defaults* *project-dir*)

#-ocicl
(when (probe-file #P"~/.local/share/ocicl/ocicl-runtime.lisp")
  (load #P"~/.local/share/ocicl/ocicl-runtime.lisp"))

;;; II. BUILDING
;; Caddy is used for SSL Termination and as a Reverse Proxy.
(push :hunchentoot-no-ssl *features*)
;; Whitespace to enhance readability in logs.
(format t "~&        *PROJECT-DIR* = ~a" (make-pathname :directory *project-dir*))
(format t "~&        COMMON-LISP-ENV = ~a:~a (Provided ASDF version ~a) on ~a~%"
        (lisp-implementation-type) (lisp-implementation-version)
        (asdf:asdf-version) (machine-type))
(format t "~&        FIXNUM BITS:~a~%" (integer-length most-positive-fixnum))
(format t "~&        FEATURES = ~a~%" *features*)

;; Bundle Slynk into the image for remote debugging. APPLICATION-TOPLEVEL uses
;; (find-package :slynk) guards so it remains optional at runtime.
(asdf:load-system :slynk)

(asdf:load-system "org.sttimothyto")
(format t "~&        ====== Build Successful | Deo Gratias ======~%")
(format t "~&        ====== END OF MAKE.LISP ======~%")
;; SBCL refuses to save a core with multiple threads running. CLOG or dbi
;; may still have spawned workers during load.
(let ((main (bordeaux-threads:current-thread)))
  (dolist (th (bordeaux-threads:all-threads))
    (unless (eq th main)
      (ignore-errors (bordeaux-threads:destroy-thread th)))))
(sleep 0.5)
;; Strip ocicl-runtime's ASDF searcher before save-lisp-and-die. At
;; runtime, asdf:system-relative-pathname re-locates :org.sttimothyto
;; via the search functions; if the searcher falls through to ocicl,
;; it spawns the `ocicl` binary to install — fatal under systemd where
;; ~/.local/bin is not on PATH. The saved image needs no further
;; system installation; all dependencies are already loaded.
(when (find-package :ocicl-runtime)
  (let ((searcher (find-symbol "SYSTEM-DEFINITION-SEARCHER"
                               :ocicl-runtime)))
    (when searcher
      (setf asdf:*system-definition-search-functions*
            (remove searcher
                    asdf:*system-definition-search-functions*)))))
(asdf:make "org.sttimothyto") ; see "org.sttimothyto.asd" for more.
;; SBCL's `save-lisp-and-die' kills the lisp process at the end.
;; However this behaviour is implementation dependent. This command
;; is here in case it does not kill the lisp process.
(uiop:quit 0)

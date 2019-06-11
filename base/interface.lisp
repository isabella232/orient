(defpackage orient.interface
  (:use :common-lisp :orient :cl-json :it.bese.FiveAm)
  (:import-from :fset :wb-map :convert)
  (:shadowing-import-from :fset :set)
  (:export :load-pipeline :load-transformation :load-tuple :load-json :<-json)
  (:nicknames :interface))

(in-package "INTERFACE")
(def-suite interface-suite)
(in-suite interface-suite)

(defvar *schema-package*)

(defun effective-schema-package-name ()
  (or (and (boundp '*schema-package*)
	   *schema-package*
	   (package-name *schema-package*))
      (package-name *package*)))

(defun schema-intern (name &key (upcase t))
  (let ((name (if upcase (string-upcase name) name)))
    (intern name (effective-schema-package-name))))

(defgeneric load-json (type-spec json-pathspec)
  (:method ((type t) (json-pathspec t))
    (load-json type (pathname json-pathspec)))
  (:method ((type t) (json-pathname pathname))    
    (let ((json (decode-json-from-source (pathname json-pathname))))
      (<-json type json))))

(defgeneric <-json (type json)
  (:method ((type (eql :pipeline)) (json list))
    (mapcar #'transformation<-parsed-json json))
  (:method ((type (eql :transformation)) (json t))
    (transformation<-json json))
  (:method ((type (eql :tuple)) (json list))
    (make-tuple json t))
  (:method ((type (eql :signature)) (json list))
    (let* ((string-inputs  (cdr (assoc :input json)))
	   (string-outputs (cdr (assoc :output json)))
	   (input (mapcar #'schema-intern string-inputs))
	   (output (mapcar #'schema-intern string-outputs)))
      (make-signature input output))))

(defun load-pipeline (json-pathspec)
  (load-json :pipeline json-pathspec))

(defun load-transformation (json-pathspec)
  (load-json :transformation json-pathspec))

(defun load-tuple (json-pathspec)
  (load-json :tuple json-pathspec))

(defmethod encode-json ((tuple wb-map) &optional stream)
 (encode-json-alist (convert 'list tuple) stream))

(defun signature-plist (signature)
  `(:input ,(convert 'list (signature-input signature)) :output ,(convert 'list (signature-output signature))))

(defmethod encode-json ((signature signature) &optional stream)
  (encode-json-plist
   (signature-plist signature)
   stream))

(defmethod encode-json ((transformation transformation) &optional stream)
  ;; TODO: handle SOURCE.
  (with-object (stream)
    (as-object-member (:transformation stream)
      (encode-json-plist
       ;; TODO: It would be better to package signatures as first-class items rather than unwrapping into the transformation. Try to have that changed.
       `(,@(signature-plist (transformation-signature transformation))
	   :implementation
	   ,(transformation-implementation transformation))
       stream))))

;; TODO: roundtrip tests
;; TODO: there must be a cleaner/clearer way to do this.
(defun transformation<-json (transformation-spec)
  (let* ((transformation-json (cdr (assoc :transformation transformation-spec))) ;; TODO: Should the spec just use :transformation?
	 (implementation-spec (cdr (assoc :implementation transformation-json)))
	 (module-name (cdr (assoc :module implementation-spec)))
	 (package-name (cond (module-name (string-upcase module-name))
			     (*schema-package* (package-name *schema-package*))
			     (t (package-name *package*))))
	 (implementation-symbol-name (cdr (assoc :name implementation-spec)))
	 (implementation (make-instance 'implementation :name implementation-symbol-name :module package-name))
	 (signature (<-json :signature transformation-json)))
    (make-instance 'transformation :signature signature :implementation implementation)))

(defun test-roundtrip (type-spec thing)
  (let* ((json-string (encode-json-to-string thing))
	 (json (decode-json-from-string json-string))
	 (returned (<-json type-spec json)))
    (is (same thing returned))))

(test transformation
  (test-roundtrip :transformation (transformation ((a b c) ~> (d e f)) == xxx)))

(test signature
  (test-roundtrip :signature (sig (q r s) -> (t u v))))

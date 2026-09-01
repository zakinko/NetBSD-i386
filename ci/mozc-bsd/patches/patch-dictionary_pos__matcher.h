$NetBSD$

clang 21 rejects [[clang::lifetimebound]] on a parameter of a function that
returns void:

  ./dictionary/pos_matcher.h:103:33: error: 'lifetimebound' attribute cannot
  be applied to a parameter of a function that returns void; did you mean
  'lifetime_capture_by(X)'

The attribute says the return value borrows from the parameter, so on a void
function it says nothing; dropping it changes no behaviour.  Upstream removed
this setter entirely -- PosMatcher now takes an absl::Span in its constructor
-- but that came with a larger rewrite of the class.

--- dictionary/pos_matcher.h.orig
+++ dictionary/pos_matcher.h
@@ -100,7 +100,7 @@
   PosMatcher(const PosMatcher &) = default;
   PosMatcher &operator=(const PosMatcher &) = default;
 
-  void Set(const uint16_t *data ABSL_ATTRIBUTE_LIFETIME_BOUND) { data_ = data; }
+  void Set(const uint16_t *data) { data_ = data; }
 
  private:
   // Used in pos_matcher_impl.inc.

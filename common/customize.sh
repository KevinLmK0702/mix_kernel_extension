# Shared customize.sh for the Mali r38p1 overlay modules.
#
# The blobs are dropped into /vendor through Magisk's overlay, so the only
# thing left to do is make sure they carry the labels the vendor policy
# expects. file_contexts entries come from Magisk's own sepolicy rules for
# /vendor, hence only the mode is fixed up here.

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/vendor/lib64/egl/libGLES_mali.so" 0 0 0644
set_perm "$MODPATH/system/vendor/lib/egl/libGLES_mali.so"   0 0 0644

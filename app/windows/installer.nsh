; Custom NSIS: window title only (no " Setup" suffix).
!macro customHeader
  Caption "${PRODUCT_NAME}"
!macroend

; Do not override customCheckAppRunning: the default warns if the app is still running.
; An empty macro used to skip that check and led to "Failed to uninstall old application files"
; when the installer ran while Electron still had files open (e.g. after clicking an update toast).

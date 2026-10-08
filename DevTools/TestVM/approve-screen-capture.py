# approve-screen-capture.py: in a fresh test VM, approves screen capture for
# Tart's guest agent for a month, as clicking Allow in macOS's prompt does, so
# `vm.sh shot` doesn't wait on a prompt nobody sees. Run it as the VM's user,
# then `killall replayd`.
import datetime
import glob
import os
import plistlib

path = os.path.expanduser("~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist")
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    with open(path, "rb") as f:
        approvals = plistlib.load(f)
except (OSError, plistlib.InvalidFileException):
    approvals = {}
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
for agent in glob.glob("/opt/homebrew/Cellar/tart-guest-agent/*/bin/tart-guest-agent"):
    approvals[agent] = {
        "kScreenCaptureAlertableUsageCount": 1,
        "kScreenCaptureApprovalLastAlerted": now,
        "kScreenCaptureApprovalLastUsed": now,
        "kScreenCapturePrivacyHintDate": now + datetime.timedelta(days=30),
        "kScreenCapturePrivacyHintPolicy": 2592000,
    }
with open(path, "wb") as f:
    plistlib.dump(approvals, f)
print("approved:", ", ".join(approvals) or "nothing (no guest agent found)")

# uiinput.py: posts mouse events in the desktop session, as a person's hand
# would, for driving windows that scripting can't reach (a VM's prompts,
# SwiftUI buttons, Mission Control). Coordinates are in points, from the top
# left of the main screen.
#
#   uiinput.py click X Y
#   uiinput.py drag X1 Y1 X2 Y2
#   uiinput.py scroll X Y LINES        (negative: down)
import ctypes
import ctypes.util
import sys
import time

quartz = ctypes.cdll.LoadLibrary(ctypes.util.find_library("ApplicationServices"))


class Point(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]


quartz.CGEventCreateMouseEvent.restype = ctypes.c_void_p
quartz.CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, Point, ctypes.c_uint32]
quartz.CGEventCreateScrollWheelEvent.restype = ctypes.c_void_p
quartz.CGEventCreateScrollWheelEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_int32]
quartz.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
quartz.CFRelease.argtypes = [ctypes.c_void_p]

MOVED, DOWN, UP, DRAGGED = 5, 1, 2, 6


def post(event):
    quartz.CGEventPost(0, event)  # the HID tap: seen like a real mouse
    quartz.CFRelease(event)


def mouse(kind, x, y):
    post(quartz.CGEventCreateMouseEvent(None, kind, Point(x, y), 0))


def click(x, y):
    for kind in (MOVED, DOWN, UP):
        mouse(kind, x, y)
        time.sleep(0.15)


def drag(x1, y1, x2, y2, steps=30):
    mouse(MOVED, x1, y1)
    time.sleep(0.2)
    mouse(DOWN, x1, y1)
    time.sleep(0.3)
    for i in range(1, steps + 1):  # Finder needs the moves in between
        mouse(DRAGGED, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
        time.sleep(0.03)
    time.sleep(0.5)
    mouse(UP, x2, y2)


def scroll(x, y, lines):
    mouse(MOVED, x, y)
    time.sleep(0.2)
    step = -1 if lines < 0 else 1
    for _ in range(abs(lines)):
        post(quartz.CGEventCreateScrollWheelEvent(None, 1, 1, step * 3))  # 1: line units, 1 wheel
        time.sleep(0.05)


def main(args):
    commands = {"click": (click, 2), "drag": (drag, 4), "scroll": (scroll, 3)}
    if not args or args[0] not in commands or len(args) - 1 != commands[args[0]][1]:
        sys.exit("usage: uiinput.py click X Y | drag X1 Y1 X2 Y2 | scroll X Y LINES")
    function, _ = commands[args[0]]
    values = [float(a) for a in args[1:]]
    if args[0] == "scroll":
        values[2] = int(values[2])
    function(*values)


if __name__ == "__main__":
    main(sys.argv[1:])

"""
A Claude panel inside Blender.

WHAT IT IS FOR
--------------
Reviewing an animation and reporting on it were two different places: you
looked in Blender, then described what you saw somewhere else, from memory,
without the frame number or the pose. Most of what makes feedback actionable -
which clip, which frame, which bone, how far off - got lost in the retelling.

This puts the conversation where the animation is. A note sent from here
carries the exact frame, the active clip, the selected bone and the current
elbow/clearance readings with it.

WHAT IT IS NOT
--------------
Not a live chat. Claude is not a background service and cannot answer the
instant you press Send; messages queue in tools/claude_chat.jsonl and are
answered next time Claude runs. In practice: type here, alt-tab, say "check
blender". Replies appear in this panel.

ANALYSE runs the same measurements the exporter uses - elbow snap, body
clearance, tip evenness - against whatever is on screen right now, so the
numbers are available without leaving Blender or waiting for anyone.

    Install: Edit > Preferences > Add-ons > Install, pick this file
    Or:      blender --python tools/claude_panel.py
"""
bl_info = {
    "name": "Claude — animation review",
    "author": "Simon + Claude",
    "version": (1, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > Claude",
    "description": "Send context-rich animation notes to Claude and read replies",
    "category": "Animation",
}

import bpy
import json
import math
import os
import time

CHAT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude_chat.jsonl")


# ---------------------------------------------------------------------------
# context capture
# ---------------------------------------------------------------------------

def _current_clip(scene):
    """Which marker's clip the playhead is inside."""
    best = None
    for m in scene.timeline_markers:
        if m.frame <= scene.frame_current and (best is None or m.frame > best.frame):
            best = m
    return (best.name, scene.frame_current - best.frame) if best else ("(none)", scene.frame_current)


def _measure(scene):
    """The exporter's metrics, run against what is on screen right now."""
    arm = bpy.data.objects.get("R15")
    wctl = bpy.data.objects.get("WeaponCtl")
    if not arm or not wctl:
        return {}

    pb = arm.pose.bones
    try:
        sh = pb["RightUpperArm"].matrix.translation
        el = pb["RightLowerArm"].matrix.translation
        wr = pb["RightHand"].matrix.translation
    except KeyError:
        return {}

    out = {}
    a, b = (sh - el), (wr - el)
    if a.length > 1e-6 and b.length > 1e-6:
        out["elbow_bend"] = round(math.degrees(a.angle(b)), 1)
    out["extension"] = round((wr - sh).length, 2)

    # Closest approach of the weapon to any body part it should not touch.
    from mathutils import Matrix
    grip = wctl.matrix_world.translation
    tip = (wctl.matrix_world @ Matrix.Translation((0, 4.4, 0))).translation
    seg = tip - grip
    L2 = seg.dot(seg)
    worst, wname = 9e9, "-"
    for name, rad in (("Head", 0.30), ("UpperTorso", 0.45), ("LowerTorso", 0.45),
                      ("RightUpperLeg", 0.30), ("LeftUpperLeg", 0.30)):
        o = bpy.data.objects.get("m_" + name)
        if not o:
            continue
        p = o.matrix_world.translation
        t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, (p - grip).dot(seg) / L2))
        d = (p - (grip + seg * t)).length - rad
        if d < worst:
            worst, wname = d, name
    if worst < 9e8:
        out["clearance"] = round(worst, 2)
        out["closest_to"] = wname
    return out


def _append(role, text, extra=None):
    rec = {"t": time.strftime("%H:%M:%S"), "role": role, "text": text}
    if extra:
        rec.update(extra)
    with open(CHAT, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def _read(limit=8):
    if not os.path.exists(CHAT):
        return []
    out = []
    with open(CHAT, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    return out[-limit:]


# ---------------------------------------------------------------------------
# operators
# ---------------------------------------------------------------------------

class CLAUDE_OT_send(bpy.types.Operator):
    bl_idname = "claude.send"
    bl_label = "Send to Claude"
    bl_description = "Queue this note with the current frame, clip and measurements attached"

    def execute(self, context):
        scene = context.scene
        note = scene.claude_message.strip()
        if not note:
            self.report({'WARNING'}, "Nothing to send")
            return {'CANCELLED'}

        clip, offset = _current_clip(scene)
        sel = context.active_pose_bone.name if context.active_pose_bone else (
            context.active_object.name if context.active_object else None)
        _append("simon", note, {
            "clip": clip,
            "frame": scene.frame_current,
            "frame_in_clip": offset,
            "selected": sel,
            "blend": os.path.basename(bpy.data.filepath),
            "metrics": _measure(scene),
        })
        scene.claude_message = ""
        self.report({'INFO'}, "Queued for Claude — say 'check blender'")
        return {'FINISHED'}


class CLAUDE_OT_analyse(bpy.types.Operator):
    bl_idname = "claude.analyse"
    bl_label = "Analyse this frame"
    bl_description = "Run the exporter's measurements against the current frame"

    def execute(self, context):
        m = _measure(context.scene)
        if not m:
            self.report({'WARNING'}, "No rig in this file")
            return {'CANCELLED'}
        clip, off = _current_clip(context.scene)
        bits = []
        if "elbow_bend" in m:
            bits.append("elbow %.0f deg" % m["elbow_bend"])
        bits.append("extension %.2f / 1.73" % m.get("extension", 0))
        if "clearance" in m:
            bits.append("clearance %+.2f (%s)" % (m["clearance"], m["closest_to"]))
        context.scene.claude_readout = "%s +%d: %s" % (clip, off, "  |  ".join(bits))
        return {'FINISHED'}


class CLAUDE_OT_refresh(bpy.types.Operator):
    bl_idname = "claude.refresh"
    bl_label = "Refresh"
    bl_description = "Re-read the conversation from disk"

    def execute(self, context):
        for a in context.screen.areas:
            a.tag_redraw()
        return {'FINISHED'}


# ---------------------------------------------------------------------------
# panel
# ---------------------------------------------------------------------------

class CLAUDE_PT_panel(bpy.types.Panel):
    bl_label = "Claude"
    bl_idname = "CLAUDE_PT_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Claude"

    def draw(self, context):
        layout = self.layout
        scene = context.scene

        clip, off = _current_clip(scene)
        box = layout.box()
        box.label(text="%s  (frame %d, +%d)" % (clip, scene.frame_current, off), icon='ANIM')
        row = box.row()
        row.operator("claude.analyse", icon='DRIVER')
        if scene.claude_readout:
            for line in scene.claude_readout.split("  |  "):
                box.label(text=line)

        layout.separator()
        layout.label(text="Note to Claude:")
        layout.prop(scene, "claude_message", text="")
        layout.operator("claude.send", icon='EXPORT')

        layout.separator()
        head = layout.row()
        head.label(text="Conversation", icon='TEXT')
        head.operator("claude.refresh", text="", icon='FILE_REFRESH')

        msgs = _read()
        if not msgs:
            layout.label(text="(nothing yet)")
        for m in msgs:
            b = layout.box()
            who = "You" if m.get("role") == "simon" else "Claude"
            b.label(text="%s  %s" % (who, m.get("t", "")),
                    icon='USER' if who == "You" else 'LIGHT')
            text = m.get("text", "")
            for chunk in [text[i:i + 34] for i in range(0, min(len(text), 340), 34)]:
                b.label(text=chunk)
            if m.get("clip"):
                b.label(text="   @ %s +%s" % (m["clip"], m.get("frame_in_clip", "?")))


CLASSES = (CLAUDE_OT_send, CLAUDE_OT_analyse, CLAUDE_OT_refresh, CLAUDE_PT_panel)


def register():
    for c in CLASSES:
        bpy.utils.register_class(c)
    bpy.types.Scene.claude_message = bpy.props.StringProperty(
        name="Message", description="What to tell Claude about this animation", default="")
    bpy.types.Scene.claude_readout = bpy.props.StringProperty(default="")


def unregister():
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)
    del bpy.types.Scene.claude_message
    del bpy.types.Scene.claude_readout


if __name__ == "__main__":
    try:
        unregister()
    except Exception:
        pass
    register()
    print("CLAUDE PANEL registered — View3D sidebar (N) > Claude")

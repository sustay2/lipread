import json
import io
import os
import mimetypes
from urllib.parse import urlparse
import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui
from utils.api import api

st.set_page_config(page_title="Question Banks", page_icon="🧠", layout="wide")
user = ensure_login_ui()

st.title("🧠 Question Banks")

# ===================== Difficulty helpers (UI <-> API) =====================
# API expects 1..3  (1=Easy, 2=Medium, 3=Hard)
DIFF_LABELS = ["Easy", "Medium", "Hard"]
LABEL_TO_NUM = {"Easy": 1, "Medium": 2, "Hard": 3}

def diff_to_label(val) -> str:
    """Convert API int (1..3) to label for UI."""
    try:
        i = int(val)
    except Exception:
        i = 1
    i = max(1, min(3, i))  # clamp 1..3
    return DIFF_LABELS[i - 1]

def label_to_num(label: str) -> int:
    """Convert UI label to API int (1..3)."""
    return LABEL_TO_NUM.get(label, 1)

# ===================== URL helpers (fix previews) =====================
def public_media_url(url: str | None, path: str | None = None) -> str | None:
    """
    Ensure the URL we hand to the browser is reachable.
    - Rewrites http://api:8000 -> PUBLIC_API_BASE (default http://localhost:8000).
    - If only a storage path exists, build from PUBLIC_MEDIA_BASE (default http://localhost:8000/media).
    """
    if not url and not path:
        return None

    u = url
    if not u and path:
        base = st.secrets.get("PUBLIC_MEDIA_BASE", "http://localhost:8000/media")
        u = f"{base.rstrip('/')}/{str(path).lstrip('/')}"

    if u and "://api:8000" in u:
        u = u.replace("http://api:8000", st.secrets.get("PUBLIC_API_BASE", "http://localhost:8000"))

    return u

def derive_path_from_url(url: str | None) -> str | None:
    """If only a URL is present, try to derive the /media relative path (best effort)."""
    if not url:
        return None
    try:
        u = urlparse(url)
        if u.path.startswith("/media/"):
            return u.path[len("/media/"):]
        return u.path.lstrip("/")
    except Exception:
        return None

# ===================== API helpers =====================
def load_banks():
    return api("GET", "/admin/question_banks")

def load_questions(bank_id: str):
    return api("GET", f"/admin/question_banks/{bank_id}/questions")

def export_bank(bank_id: str):
    return api("GET", f"/admin/question_banks/{bank_id}/export")

def import_questions(bank_id: str, payload: dict):
    return api("POST", f"/admin/question_banks/{bank_id}/import", json=payload)

def bulk_delete(bank_id: str, ids: list[str]):
    return api("POST", f"/admin/question_banks/{bank_id}/questions:bulk_delete", json={"ids": ids})

def upload_qb_media(file_obj):
    files = {"file": (file_obj.name, file_obj.getvalue(), file_obj.type or "application/octet-stream")}
    return api("POST", "/admin/question_banks/upload_media", files=files, data={})

# ===================== Media preview (supports backend-resolved + fresh upload) =====================
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
VIDEO_EXTS = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"}

def _guess_kind_from_any(url: str | None, storage_path: str | None, content_type: str | None) -> str | None:
    ct = (content_type or "").lower()
    if ct.startswith("image/"):
        return "image"
    if ct.startswith("video/"):
        return "video"

    path = storage_path or ""
    ext = os.path.splitext(path.lower())[1]
    if ext in IMAGE_EXTS:
        return "image"
    if ext in VIDEO_EXTS:
        return "video"

    if url:
        ext_u = os.path.splitext(urlparse(url).path.lower())[1]
        if ext_u in IMAGE_EXTS:
            return "image"
        if ext_u in VIDEO_EXTS:
            return "video"
        mt, _ = mimetypes.guess_type(url)
        if mt:
            if mt.startswith("image/"):
                return "image"
            if mt.startswith("video/"):
                return "video"
    return None

def media_preview(m: dict | None):
    """Preview either backend-resolved media (q['media']) OR fresh upload response."""
    if not m:
        return

    # Normalize keys from either source
    url = public_media_url(m.get("url"), m.get("storagePath") or m.get("imagePath") or m.get("videoPath"))
    thumb_url = public_media_url(m.get("thumbUrl"), m.get("thumbPath"))
    storage_path = m.get("storagePath") or m.get("imagePath") or m.get("videoPath")
    kind = (m.get("kind")
            or _guess_kind_from_any(url, storage_path, m.get("contentType")))

    if kind == "image":
        if url:
            st.image(url, caption=m.get("title") or "Image", width=240)
        else:
            st.caption(f"(image) {storage_path}")
    elif kind == "video":
        # try real video first
        if url:
            st.video(url)
        elif thumb_url:
            st.image(thumb_url, caption="Video thumbnail", width=240)
        if storage_path or m.get("videoId"):
            st.caption(f"Video: {storage_path or m.get('videoId')}")
    else:
        # show something for debugging
        if url:
            st.write(url)
        st.json(m)

# ===================== List banks =====================
banks = load_banks()
with st.expander("All Banks", expanded=True):
    rows = [{**b, "difficultyLabel": diff_to_label(b.get("difficulty", 1))} for b in (banks or [])]
    st.dataframe(rows, use_container_width=True, height=260)

# ===================== Create bank =====================
if require_role_ui("admin", "content_editor"):
    st.divider()
    st.subheader("Create Bank")

    with st.form("create_bank"):
        c1, c2 = st.columns(2)
        with c1:
            title = st.text_input("Title")
            topic = st.text_input("Topic")
            diff_label = st.selectbox("Difficulty", DIFF_LABELS, index=0)
        with c2:
            tags_raw = st.text_input("Tags (comma separated)")
        submitted = st.form_submit_button("Create")

    if submitted:
        payload = {
            "title": title.strip(),
            "topic": topic.strip() or None,
            "difficulty": label_to_num(diff_label),  # 1..3
            "tags": [t.strip() for t in tags_raw.split(",") if t.strip()],
        }
        out = api("POST", "/admin/question_banks", json=payload)
        st.success(f"Created bank {out['id']}")
        st.rerun()

# ===================== Pick a bank =====================
st.divider()
st.subheader("Manage a Bank")

bank_ids = [b["id"] for b in (banks or [])]
bank_labels = [
    f"({diff_to_label(b.get('difficulty',1))}) {b.get('title','(untitled)')} [{b['id']}]"
    for b in (banks or [])
]

if "qb_selected_idx" not in st.session_state:
    st.session_state["qb_selected_idx"] = 0

if bank_ids:
    sel_idx = st.selectbox(
        "Select Bank",
        options=list(range(len(bank_ids))),
        format_func=lambda i: bank_labels[i],
        index=st.session_state["qb_selected_idx"],
        key="qb_select",
    )
    st.session_state["qb_selected_idx"] = sel_idx
    bank_id = bank_ids[sel_idx]

    # ----- Bank actions
    if require_role_ui("admin", "content_editor"):
        with st.expander("Edit / Delete Bank", expanded=False):
            c1, c2, c3, c4 = st.columns(4)
            with c1:
                new_title = st.text_input("Title (edit)", value=banks[sel_idx].get("title") or "")
            with c2:
                new_topic = st.text_input("Topic (edit)", value=banks[sel_idx].get("topic") or "")
            with c3:
                diff_label_edit = st.selectbox(
                    "Difficulty",
                    DIFF_LABELS,
                    index=DIFF_LABELS.index(diff_to_label(banks[sel_idx].get("difficulty", 1))),
                    key="bank_diff_edit",
                )
            with c4:
                new_tags = st.text_input("Tags (comma)", value=",".join(banks[sel_idx].get("tags", [])))

            colA, colB, colC = st.columns(3)
            with colA:
                if st.button("Save changes"):
                    patch = {
                        "title": new_title.strip() or None,
                        "topic": new_topic.strip() or None,
                        "difficulty": label_to_num(diff_label_edit),  # 1..3
                        "tags": [t.strip() for t in new_tags.split(",") if t.strip()],
                    }
                    api("PATCH", f"/admin/question_banks/{bank_id}", json=patch)
                    st.success("Bank updated.")
                    st.rerun()
            with colB:
                if st.button("Soft delete (archive)"):
                    api("DELETE", f"/admin/question_banks/{bank_id}", json=None)
                    st.success("Bank archived.")
                    st.rerun()
            with colC:
                if st.button("Hard delete (with questions)"):
                    api("DELETE", f"/admin/question_banks/{bank_id}?hard=true", json=None)
                    st.success("Bank and all questions deleted.")
                    st.rerun()

        with st.expander("Export / Import", expanded=False):
            col1, col2 = st.columns(2)
            with col1:
                if st.button("Export as JSON"):
                    data = export_bank(bank_id)
                    buf = io.BytesIO(json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8"))
                    st.download_button(
                        "Download export.json",
                        data=buf,
                        file_name=f"{bank_id}_export.json",
                        mime="application/json",
                    )
            with col2:
                up = st.file_uploader("Import JSON", type=["json"])
                mode = st.selectbox("Import mode", ["append", "replace"], index=0)
                if up and st.button("Run import"):
                    try:
                        payload = json.load(up)
                        questions = payload if isinstance(payload, list) else payload.get("questions") or payload.get("items") or []
                        res = import_questions(bank_id, {"mode": mode, "questions": questions})
                        st.success(f"Imported {res.get('imported',0)} (replaced {res.get('replaced',0)}).")
                        st.rerun()
                    except Exception as e:
                        st.error(f"Import failed: {e}")

    # ===================== Questions list/edit =====================
    qs = load_questions(bank_id)
    with st.expander("Questions", expanded=True):
        st.caption("Select a question to edit/delete. Use bulk delete for many.")

        q_ids = [q["id"] for q in qs]
        q_labels = [f"{q.get('type','mcq')} · {q.get('stem','')[:60]} [{q['id']}]" for q in qs]

        if "q_selected_idx" not in st.session_state:
            st.session_state["q_selected_idx"] = 0

        if q_ids:
            qidx = st.selectbox(
                "Pick question",
                options=list(range(len(q_ids))),
                format_func=lambda i: q_labels[i],
                index=st.session_state["q_selected_idx"],
                key="qb_q_select",
            )
            st.session_state["q_selected_idx"] = qidx
            q = qs[qidx]

            # temp state for newly uploaded media (not yet saved)
            if "qb_edit_media_upload" not in st.session_state:
                st.session_state["qb_edit_media_upload"] = None

            with st.form("edit_question"):
                qtype = st.selectbox("Type", ["mcq", "fitb", "open"], index=["mcq", "fitb", "open"].index(q.get("type", "mcq")))
                stem = st.text_area("Stem", value=q.get("stem", ""), height=80)

                # --- Media block (optional for ANY type)
                st.markdown("**Media (optional)**")
                # Show current (resolved from API) unless a fresh upload is in session state
                current_media = st.session_state["qb_edit_media_upload"] or (q.get("media") or {})
                media_preview(current_media if isinstance(current_media, dict) else {})

                upcol1, upcol2 = st.columns([2, 1])
                with upcol1:
                    new_file = st.file_uploader(
                        "Upload image/video",
                        type=["jpg", "jpeg", "png", "webp", "gif", "mp4", "mov", "m4v", "webm", "avi", "mkv"],
                        key="edit_q_media_upl",
                    )
                with upcol2:
                    remove_media = st.checkbox("Remove media", value=False, key="edit_q_media_rm")

                uploaded = st.session_state["qb_edit_media_upload"]
                if new_file:
                    try:
                        res = upload_qb_media(new_file)  # returns {id, url, storagePath, kind, ...}
                        st.session_state["qb_edit_media_upload"] = res
                        st.success("Media uploaded.")
                    except Exception as e:
                        st.error(f"Upload failed: {e}")

                options = q.get("options", [])
                answers = q.get("answers", [])
                answerPattern = q.get("answerPattern")

                if qtype == "mcq":
                    st.caption("Options (2–6)")
                    o1 = st.text_input("Option 1", value=options[0] if len(options) > 0 else "")
                    o2 = st.text_input("Option 2", value=options[1] if len(options) > 1 else "")
                    o3 = st.text_input("Option 3", value=options[2] if len(options) > 2 else "")
                    o4 = st.text_input("Option 4", value=options[3] if len(options) > 3 else "")
                    o5 = st.text_input("Option 5", value=options[4] if len(options) > 4 else "")
                    o6 = st.text_input("Option 6", value=options[5] if len(options) > 5 else "")
                    options = [x for x in [o1, o2, o3, o4, o5, o6] if x]
                    answers = st.multiselect("Correct answers", options, default=[a for a in answers if a in options])
                    answerPattern = None
                elif qtype == "fitb":
                    answers_raw = st.text_input("Acceptable answers (comma)", value=",".join(answers))
                    answers = [a.strip() for a in answers_raw.split(",") if a.strip()]
                    answerPattern = st.text_input("Regex pattern (optional)", value=answerPattern or "")
                else:
                    options, answers, answerPattern = [], [], None

                diff_label_q = st.selectbox(
                    "Question difficulty",
                    DIFF_LABELS,
                    index=DIFF_LABELS.index(diff_to_label(q.get("difficulty", 1))),
                    key="q_diff_edit",
                )

                explanation = st.text_area("Explanation", value=q.get("explanation") or "", height=80)
                tags_raw = st.text_input("Tags (comma)", value=",".join(q.get("tags", [])))

                cA, cB = st.columns(2)
                with cA:
                    save_q = st.form_submit_button("Save")
                with cB:
                    delete_q = st.form_submit_button("Delete")

            if save_q and require_role_ui("admin", "content_editor"):
                patch = {
                    "type": qtype,
                    "stem": stem.strip(),
                    "options": options,
                    "answers": answers,
                    "answerPattern": (answerPattern or None) if qtype == "fitb" else None,
                    "explanation": (explanation.strip() or None),
                    "tags": [t.strip() for t in tags_raw.split(",") if t.strip()],
                    "difficulty": label_to_num(diff_label_q),  # 1..3
                }
                # mediaId logic:
                if remove_media:
                    patch["mediaId"] = None
                elif st.session_state["qb_edit_media_upload"]:
                    patch["mediaId"] = st.session_state["qb_edit_media_upload"].get("id")

                api("PATCH", f"/admin/question_banks/{bank_id}/questions/{q['id']}", json=patch)
                st.success("Question updated.")
                st.session_state["qb_edit_media_upload"] = None
                st.rerun()

            if delete_q and require_role_ui("admin"):
                api("DELETE", f"/admin/question_banks/{bank_id}/questions/{q['id']}")
                st.success("Question deleted.")
                st.session_state["qb_edit_media_upload"] = None
                st.rerun()

        # Bulk delete
        if require_role_ui("admin"):
            st.markdown("#### Bulk delete")
            to_delete = st.multiselect(
                "Pick questions to delete",
                options=q_ids,
                format_func=lambda i: next((lbl for lbl, _id in zip(q_labels, q_ids) if _id == i), i),
            )
            if to_delete and st.button(f"Delete {len(to_delete)} selected"):
                bulk_delete(bank_id, to_delete)
                st.success(f"Deleted {len(to_delete)} questions.")
                st.rerun()

    # ===================== Add new question =====================
    if require_role_ui("admin", "content_editor"):
        st.markdown("### Add Question")
        q_type = st.selectbox("Type", ["mcq", "fitb", "open"], index=0)

        if "qb_new_q_media" not in st.session_state:
            st.session_state["qb_new_q_media"] = None  # stores upload response for preview + id

        with st.form("add_question"):
            stem = st.text_area("Stem", height=80, placeholder="Enter the question text...")

            st.markdown("**Media (optional)**")
            media_preview(st.session_state["qb_new_q_media"])
            upl_new = st.file_uploader(
                "Upload image/video",
                type=["jpg", "jpeg", "png", "webp", "gif", "mp4", "mov", "m4v", "webm", "avi", "mkv"],
                key="new_q_media_upl",
            )
            rm_new_media = st.checkbox("Remove media (if any)", value=False, key="new_q_media_rm")
            if upl_new:
                try:
                    res = upload_qb_media(upl_new)  # {id, url, storagePath, kind, ...}
                    st.session_state["qb_new_q_media"] = res
                    st.success("Media uploaded.")
                except Exception as e:
                    st.error(f"Upload failed: {e}")
            if rm_new_media:
                st.session_state["qb_new_q_media"] = None

            options, answers, answerPattern = [], [], None
            if q_type == "mcq":
                st.caption("Options (2–6)")
                o1 = st.text_input("Option 1"); o2 = st.text_input("Option 2")
                o3 = st.text_input("Option 3", value=""); o4 = st.text_input("Option 4", value="")
                o5 = st.text_input("Option 5", value=""); o6 = st.text_input("Option 6", value="")
                options = [x for x in [o1, o2, o3, o4, o5, o6] if x]
                answers = st.multiselect("Correct answers", options)
            elif q_type == "fitb":
                answers_raw = st.text_input("Acceptable answers (comma)", value="")
                answerPattern = st.text_input("Regex pattern (optional)", value="")
                answers = [a.strip() for a in answers_raw.split(",") if a.strip()]
                answerPattern = (answerPattern or "").strip() or None

            explanation = st.text_area("Explanation", value="", height=80)
            tags_raw = st.text_input("Tags (comma separated)")
            diff_label_new = st.selectbox("Question difficulty", DIFF_LABELS, index=0, key="q_diff_new")

            submit_new = st.form_submit_button("Add Question")

        if submit_new:
            payload = {
                "type": q_type,
                "stem": stem.strip(),
                "options": options,
                "answers": answers,
                "answerPattern": answerPattern,
                "explanation": explanation.strip() or None,
                "tags": [t.strip() for t in tags_raw.split(",") if t.strip()],
                "difficulty": label_to_num(diff_label_new),  # 1..3
            }
            if st.session_state["qb_new_q_media"]:
                payload["mediaId"] = st.session_state["qb_new_q_media"].get("id")
            out = api("POST", f"/admin/question_banks/{bank_id}/questions", json=payload)
            st.success(f"Added question {out['id']}")
            st.session_state["qb_new_q_media"] = None
            st.rerun()
else:
    st.info("Create a question bank first.")
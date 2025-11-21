import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui
from utils.api import api
import os

PUBLIC_API_BASE = os.getenv("PUBLIC_API_BASE", "http://localhost:8000")

def _to_public(u: str | None) -> str | None:
    if not u:
        return None
    return u.replace("http://api:8000", PUBLIC_API_BASE)

st.set_page_config(page_title="Media Library", page_icon="🎞️", layout="wide")
user = ensure_login_ui()

st.title("🎞️ Media Library")

with st.expander("⬆️ Upload new media", expanded=False):
    up_col1, up_col2 = st.columns([3, 2])
    with up_col1:
        file_obj = st.file_uploader(
            "Choose a video/audio file",
            type=["mp4", "mov", "m4v", "avi", "mkv", "webm", "mp3", "wav", "m4a"],
            accept_multiple_files=False,
        )
        title = st.text_input("Title (optional)")
        language = st.text_input("Language", value="en")
        speaker_id = st.text_input("Speaker ID (optional)", value="")
    with up_col2:
        license_val = st.selectbox("License", ["internal", "open", "commercial"], index=0)
        source_val = st.text_input("Source", value="manual")
        st.caption("Uploads go to `/admin/videos` and will appear here after processing.")
        if st.button("Upload"):
            if not file_obj:
                st.error("Please choose a file.")
            else:
                try:
                    files = {
                        "file": (
                            file_obj.name,
                            file_obj.getvalue(),
                            file_obj.type or "application/octet-stream",
                        )
                    }
                    data = {
                        "title": title,
                        "language": language,
                        "speakerId": speaker_id or "",
                        "license": license_val,
                        "source": source_val,
                    }
                    api("POST", "/admin/videos/upload", files=files, data=data)
                    st.success("Upload complete. Generating metadata/thumbnail…")
                    st.cache_data.clear()
                    st.rerun()
                except Exception as e:
                    st.error(f"Upload failed: {e}")

@st.cache_data(ttl=15.0)
def load_media_or_videos(q: str = "", limit: int = 200):
    items = []
    source = "media"
    try:
        data = api("GET", f"/admin/media?limit={limit}" + (f"&q={q}" if q else ""))
        items = data.get("items", []) if isinstance(data, dict) else (data or [])
        for it in items:
            it["_source"] = "media"
            it["path"] = it.get("path") or it.get("storagePath") or it.get("sourcePath")
    except Exception:
        items = []

    if not items:
        try:
            vdata = api("GET", f"/admin/videos?limit={limit}" + (f"&q={q}" if q else ""))
            vitems = vdata.get("items", []) if isinstance(vdata, dict) else (vdata or [])
            for v in vitems:
                v["_source"] = "videos"
                v["path"] = v.get("path") or v.get("storagePath")
            items = vitems
            source = "videos"
        except Exception:
            items = []
            source = "media"

    return items, source

def regenerate_one(item):
    src = item.get("_source") or "media"
    mid = item["id"]
    ep = "/admin/media/{id}:thumbnail" if src == "media" else "/admin/videos/{id}:thumbnail"
    try:
        api("POST", ep.format(id=mid), json={})
        st.success("Thumbnail requested/generated.")
        st.cache_data.clear()
        st.rerun()
    except Exception as e:
        st.error(f"Failed: {e}")

def regenerate_batch(selected_items):
    if not selected_items:
        st.warning("Select at least one item.")
        return
    media_ids = [it["id"] for it in selected_items if it.get("_source") == "media"]
    video_items = [it for it in selected_items if it.get("_source") == "videos"]

    if media_ids:
        try:
            api("POST", "/admin/media/thumbnails:batch", json={"ids": media_ids})
        except Exception as e:
            st.error(f"Media batch failed: {e}")

    for it in video_items:
        try:
            api("POST", f"/admin/videos/{it['id']}:thumbnail", json={})
        except Exception as e:
            st.error(f"Video thumb failed for {it['id']}: {e}")

    st.success("Thumbnail generation requested.")
    st.cache_data.clear()
    st.rerun()

def do_rename(item, new_title: str, rename_file: bool):
    src = item.get("_source") or "media"
    mid = item["id"]
    ep = "/admin/media/{id}" if src == "media" else "/admin/videos/{id}"
    try:
        api("PATCH", ep.format(id=mid), json={"title": new_title, "renameFile": bool(rename_file)})
        st.success("Saved.")
        st.cache_data.clear()
        st.rerun()
    except Exception as e:
        st.error(f"Rename failed: {e}")

def do_delete(item, hard: bool):
    src = item.get("_source") or "media"
    mid = item["id"]
    ep = "/admin/media/{id}?hard={flag}" if src == "media" else "/admin/videos/{id}?hard={flag}"
    try:
        api("DELETE", ep.format(id=mid, flag=str(hard).lower()))
        st.success("Deleted." if hard else "Archived.")
        st.cache_data.clear()
        st.rerun()
    except Exception as e:
        st.error(f"Delete failed: {e}")

c1, c2, c3, c4 = st.columns([3, 2, 2, 2])
with c1:
    q = st.text_input("Search title/path", value=st.session_state.get("media_q", ""))
    st.session_state["media_q"] = q
with c2:
    limit = st.number_input("Limit", min_value=10, max_value=500, value=200, step=10)
with c3:
    select_all = st.checkbox("Select all", value=False, key="media_select_all")
with c4:
    if st.button("Reload"):
        st.cache_data.clear()
        st.rerun()

items, active_source = load_media_or_videos(q, limit)

if not items:
    st.info("No media found.")
    st.caption("This page reads /admin/media first, then falls back to /admin/videos.")
    st.stop()

st.write(f"Showing {len(items)} item(s) — source: **{active_source}**")

selected_ids = set(st.session_state.get("media_selected_ids", set()))
if select_all:
    selected_ids = {i["id"] for i in items}
st.session_state["media_selected_ids"] = selected_ids

header = st.columns([1, 1.5, 4, 2.5, 2.5, 2])
with header[0]: st.caption("")
with header[1]: st.caption("Preview")
with header[2]: st.caption("Title / Path")
with header[3]: st.caption("Info")
with header[4]: st.caption("Thumb")
with header[5]: st.caption("Actions")

IMG_WIDTH = 140

for it in items:
    mid = it.get("id")
    title = it.get("title") or "(untitled)"
    path = it.get("path") or it.get("storagePath") or "—"
    thumb_url = it.get("thumbUrl")
    thumbs_pending = it.get("thumbsPending", False)

    cols = st.columns([1, 1.5, 4, 2.5, 2.5, 2])

    with cols[0]:
        checked = st.checkbox("", value=(mid in selected_ids), key=f"sel_{mid}")
        if checked: selected_ids.add(mid)
        else: selected_ids.discard(mid)
        st.session_state["media_selected_ids"] = selected_ids

    with cols[1]:
        preview_url = _to_public(thumb_url)
        
        if preview_url:
            st.image(preview_url, width=120)
        else:
            st.write("—")

    with cols[2]:
        st.write(f"**{title}**  ·  `{it.get('_source','media')}`")
        st.caption(path)
        with st.popover("Rename", use_container_width=True):
            new_title = st.text_input("New title", value=title, key=f"ttl_{mid}")
            rename_file = st.checkbox("Also rename file (local only)", value=False, key=f"rn_{mid}")
            if st.button("Save", key=f"sv_{mid}"):
                do_rename(it, new_title.strip() or title, rename_file)

    with cols[3]:
        st.caption(f"Duration: {it.get('durationSec','—')}")
        st.caption(f"FPS: {it.get('fps','—')}")
        st.caption(f"Created: {it.get('createdAt','—')}")

    with cols[4]:
        if thumbs_pending:
            st.warning("Pending")
        if st.button("Generate thumb", key=f"gth_{mid}"):
            regenerate_one(it)
        if thumb_url:
            st.caption("✅ ready")

    with cols[5]:
        if require_role_ui("admin"):
            if st.button("Archive", key=f"arc_{mid}"):
                do_delete(it, hard=False)
            if st.button("Delete", key=f"del_{mid}", type="secondary"):
                do_delete(it, hard=True)

st.markdown("---")
left, right = st.columns([3, 2])
with left:
    sel_items = [it for it in items if it["id"] in selected_ids]
    st.write(f"Selected: {len(sel_items)}")
with right:
    c1, c2 = st.columns(2)
    with c1:
        if st.button("Generate thumbnails for selected"):
            regenerate_batch(sel_items)
    with c2:
        if require_role_ui("admin") and st.button("Archive selected"):
            for it in sel_items:
                do_delete(it, hard=False)
import streamlit as st
from utils.auth import ensure_login_ui, current_roles, require_role_ui
from utils.api import api

st.set_page_config(page_title="Courses", page_icon="📚", layout="wide")
user = ensure_login_ui()

st.title("📚 Courses")
if not require_role_ui("admin", "content_editor", "instructor"):
    st.stop()

with st.sidebar:
    st.subheader("Filters")
    q = st.text_input("Search title contains")
    include_archived = st.checkbox("Include archived", value=False)
    if st.button("Refresh"):
        st.session_state.pop("_courses", None)

if "_courses" not in st.session_state:
    try:
        res = api("GET", "/admin/courses")
        if isinstance(res, list):
            st.session_state["_courses"] = res
        elif isinstance(res, dict):
            st.session_state["_courses"] = res.get("items", [])
        else:
            st.session_state["_courses"] = []
    except Exception as e:
        st.error(f"Failed to load courses: {e}")
        st.session_state["_courses"] = []

rows = [c for c in st.session_state["_courses"] if (include_archived or not c.get("isArchive", False))]
if q:
    rows = [c for c in rows if q.lower() in c.get("title", "").lower()]

st.dataframe(rows, use_container_width=True, height=320)

st.divider()
st.subheader("Create Course")
if require_role_ui("admin", "content_editor"):
    with st.form("create_course"):
        col1, col2 = st.columns(2)
        with col1:
            title = st.text_input("Title")
            summary = st.text_area("Summary", height=80)
            difficulty = st.selectbox("Difficulty", ["", "beginner", "intermediate", "advanced"], index=0)
            locale = st.text_input("Locale", value="en")
        with col2:
            tags = st.text_input("Tags (comma separated)")
            published = st.checkbox("Published", value=False)
            order = st.number_input("Order", value=0, step=1)
        submitted = st.form_submit_button("Create")
    if submitted:
        payload = {
            "title": title.strip(),
            "summary": summary.strip() if summary else None,
            "difficulty": difficulty or None,
            "tags": [t.strip() for t in tags.split(",") if t.strip()],
            "published": published,
            "order": int(order),
            "locale": locale.strip() or "en",
        }
        out = api("POST", "/admin/courses", json=payload)
        st.success(f"Created {out['id']}")
        st.session_state.pop("_courses", None)
        st.rerun()

st.divider()
st.subheader("Edit Course")
if require_role_ui("admin", "content_editor"):
    course_id = st.text_input("Course ID to edit")
    if course_id:
        try:
            course = api("GET", f"/admin/courses/{course_id}")
        except Exception as e:
            st.error(str(e))
            course = None
        if course:
            with st.form("edit_course"):
                col1, col2 = st.columns(2)
                with col1:
                    title = st.text_input("Title", value=course.get("title",""))
                    summary = st.text_area("Summary", value=course.get("summary",""), height=80)
                    difficulty = st.selectbox("Difficulty", ["beginner","intermediate","advanced"], index=["beginner","intermediate","advanced"].index(course.get("difficulty","beginner")))
                    locale = st.text_input("Locale", value=course.get("locale","en"))
                with col2:
                    tags = st.text_input("Tags (comma separated)", value=", ".join(course.get("tags", [])))
                    published = st.checkbox("Published", value=course.get("published", False))
                    order = st.number_input("Order", value=int(course.get("order", 0)), step=1)
                    isArchive = st.checkbox("Archived", value=course.get("isArchive", False))
                save = st.form_submit_button("Save Changes")
            if save:
                patch = {
                    "title": title.strip(),
                    "summary": summary.strip() if summary else None,
                    "difficulty": difficulty,
                    "tags": [t.strip() for t in tags.split(",") if t.strip()],
                    "published": published,
                    "order": int(order),
                    "locale": locale.strip() or "en",
                    "isArchive": bool(isArchive),
                }
                out = api("PATCH", f"/admin/courses/{course_id}", json=patch)
                st.success("Updated.")
                st.session_state.pop("_courses", None)
                st.rerun()

st.divider()
st.subheader("Delete Course (Admin)")
if require_role_ui("admin"):
    del_id = st.text_input("Course ID to delete")
    hard = st.checkbox("Hard delete (cannot be undone)")
    if st.button("Delete") and del_id:
        out = api("DELETE", f"/admin/courses/{del_id}?hard={str(hard).lower()}")
        st.success(f"Deleted: {out}")
        st.session_state.pop("_courses", None)
        st.rerun()
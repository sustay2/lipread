import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui
from utils.api import api

st.set_page_config(page_title="Modules & Lessons", page_icon="🧱", layout="wide")
user = ensure_login_ui()

def load_courses():
    try:
        data = api("GET", "/admin/courses")
        return data if isinstance(data, list) else data.get("items", [])
    except Exception as e:
        st.error(f"Failed to load courses: {e}")
        return []

def load_modules(course_id):
    if not course_id: return []
    try:
        return api("GET", f"/admin/modules?courseId={course_id}")
    except Exception as e:
        st.error(f"Failed to load modules: {e}")
        return []

def load_lessons(course_id, module_id):
    if not (course_id and module_id): return []
    try:
        return api("GET", f"/admin/lessons?courseId={course_id}&moduleId={module_id}")
    except Exception as e:
        st.error(f"Failed to load lessons: {e}")
        return []

def reorder_modules(course_id, ids):
    return api("POST", f"/admin/modules/reorder?courseId={course_id}", json={"ids": ids})

def reorder_lessons(course_id, module_id, ids):
    return api("POST", f"/admin/lessons/reorder?courseId={course_id}&moduleId={module_id}", json={"ids": ids})

st.title("🧱 Modules & Lessons")

if "_courses_cache" not in st.session_state:
    st.session_state["_courses_cache"] = load_courses()

courses = st.session_state["_courses_cache"]
course_labels = ["< pick a course >"] + [c.get("title", f"(untitled {c.get('id')})") for c in courses]
course_ids = [None] + [c.get("id") for c in courses]

selected_course_idx = st.selectbox(
    "Course", options=list(range(len(course_ids))),
    format_func=lambda i: course_labels[i],
    key="ml_course_idx", index=st.session_state.get("ml_course_idx", 0),
)
selected_course_id = course_ids[selected_course_idx]

st.divider()

st.subheader("Modules")

modules = load_modules(selected_course_id) if selected_course_id else []

def _module_row(m, i):
    cols = st.columns([8, 2, 5, 2, 2, 2])
    with cols[0]: st.write(f"**{m.get('title','(untitled)')}**")
    with cols[1]: st.write(m.get("order", i))
    with cols[2]: st.caption(m.get("summary",""))
    with cols[3]:
        if st.button("⬆️", key=f"mod_up_{m['id']}", help="Move up", disabled=i==0):
            ids = [x["id"] for x in modules]
            ids[i-1], ids[i] = ids[i], ids[i-1]
            reorder_modules(selected_course_id, ids)
            st.rerun()
    with cols[4]:
        if st.button("⬇️", key=f"mod_dn_{m['id']}", help="Move down", disabled=i==len(modules)-1):
            ids = [x["id"] for x in modules]
            ids[i+1], ids[i] = ids[i], ids[i+1]
            reorder_modules(selected_course_id, ids)
            st.rerun()
    with cols[5]:
        with st.popover("⋯", use_container_width=True):
            new_title = st.text_input("Title", value=m.get("title",""), key=f"mod_title_{m['id']}")
            new_summary = st.text_area("Summary", value=m.get("summary",""), key=f"mod_sum_{m['id']}", height=80)
            if st.button("Save", key=f"mod_save_{m['id']}"):
                api("PATCH", f"/admin/modules/{m['id']}", json={"title": new_title.strip(), "summary": new_summary.strip()})
                st.rerun()
            if st.button("Delete", key=f"mod_del_{m['id']}", type="secondary"):
                api("DELETE", f"/admin/modules/{m['id']}")
                st.rerun()

if selected_course_id:
    if modules:
        header = st.columns([8,2,5,2,2,2])
        with header[0]: st.caption("Title")
        with header[1]: st.caption("Order")
        with header[2]: st.caption("Summary")
        with header[3]: st.caption("")
        with header[4]: st.caption("")
        with header[5]: st.caption("Actions")

        for idx, m in enumerate(modules):
            _module_row(m, idx)
    else:
        st.info("No modules yet.")

    if require_role_ui("admin", "content_editor"):
        with st.form("create_module"):
            st.markdown("**Create Module**")
            mod_title = st.text_input("Module title")
            mod_summary = st.text_area("Summary", height=80)
            if st.form_submit_button("Add Module"):
                api("POST", f"/admin/modules?courseId={selected_course_id}", json={"title": mod_title, "summary": mod_summary})
                st.rerun()
else:
    st.info("Pick a course to manage modules and lessons.")
    st.stop()

st.divider()

st.subheader("Lessons")

mod_labels = ["< pick a module >"] + [f"{m.get('order',0)} · {m.get('title','(untitled)')}" for m in modules]
mod_ids = [None] + [m["id"] for m in modules]
selected_module_idx = st.selectbox(
    "Module", options=list(range(len(mod_ids))),
    format_func=lambda i: mod_labels[i],
    key="ml_module_idx", index=st.session_state.get("ml_module_idx", 0),
)
selected_module_id = mod_ids[selected_module_idx]

if selected_module_id:
    lessons = load_lessons(selected_course_id, selected_module_id)

    def _lesson_row(l, i):
        cols = st.columns([8,2,5,2,2,2])
        with cols[0]: st.write(f"**{l.get('title','(untitled)')}**")
        with cols[1]: st.write(l.get("order", i))
        with cols[2]:
            mins = int(l.get("estimatedMin", 5))
            st.caption(f"{mins} min")
        with cols[3]:
            if st.button("⬆️", key=f"les_up_{l['id']}", disabled=i==0):
                ids = [x["id"] for x in lessons]
                ids[i-1], ids[i] = ids[i], ids[i-1]
                reorder_lessons(selected_course_id, selected_module_id, ids)
                st.rerun()
        with cols[4]:
            if st.button("⬇️", key=f"les_dn_{l['id']}", disabled=i==len(lessons)-1):
                ids = [x["id"] for x in lessons]
                ids[i+1], ids[i] = ids[i], ids[i+1]
                reorder_lessons(selected_course_id, selected_module_id, ids)
                st.rerun()
        with cols[5]:
            with st.popover("⋯", use_container_width=True):
                new_title = st.text_input("Title", value=l.get("title",""), key=f"les_title_{l['id']}")
                new_mins = st.number_input("Estimated minutes", value=int(l.get("estimatedMin",5)), step=1, min_value=1, key=f"les_min_{l['id']}")
                obj_raw = ", ".join(l.get("objectives", []))
                obj_str = st.text_area("Objectives (comma separated)", value=obj_raw, key=f"les_obj_{l['id']}")
                if st.button("Save", key=f"les_save_{l['id']}"):
                    patch = {
                        "title": new_title.strip(),
                        "estimatedMin": int(new_mins),
                        "objectives": [x.strip() for x in obj_str.split(",") if x.strip()],
                    }
                    api("PATCH", f"/admin/lessons/{l['id']}", json=patch)
                    st.rerun()
                if st.button("Delete", key=f"les_del_{l['id']}", type="secondary"):
                    api("DELETE", f"/admin/lessons/{l['id']}")
                    st.rerun()

    if lessons:
        header = st.columns([8,2,5,2,2,2])
        with header[0]: st.caption("Title")
        with header[1]: st.caption("Order")
        with header[2]: st.caption("Est.")
        with header[3]: st.caption("")
        with header[4]: st.caption("")
        with header[5]: st.caption("Actions")

        for idx, l in enumerate(lessons):
            _lesson_row(l, idx)
    else:
        st.info("No lessons yet.")

    if require_role_ui("admin", "content_editor"):
        with st.form("create_lesson"):
            st.markdown("**Create Lesson**")
            less_title = st.text_input("Lesson title")
            less_order_est = st.number_input("Estimated minutes", value=5, step=1, min_value=1)
            less_obj_raw = st.text_area("Objectives (comma separated)")
            if st.form_submit_button("Add Lesson"):
                payload = {
                    "title": less_title,
                    "estimatedMin": int(less_order_est),
                    "objectives": [x.strip() for x in less_obj_raw.split(",") if x.strip()],
                }
                api("POST", f"/admin/lessons?courseId={selected_course_id}&moduleId={selected_module_id}", json=payload)
                st.rerun()
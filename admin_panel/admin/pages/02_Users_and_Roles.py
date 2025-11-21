import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui, current_roles
from utils.api import api
from datetime import datetime

st.set_page_config(page_title="Users & Roles", page_icon="👥", layout="wide")

user = ensure_login_ui()

st.title("👥 Users & Roles")
if not require_role_ui("admin"):
    st.stop()

if "_users_prev_stack" not in st.session_state:
    st.session_state["_users_prev_stack"] = []

if "_users_cursor" not in st.session_state:
    st.session_state["_users_cursor"] = None

if "_users_limit" not in st.session_state:
    st.session_state["_users_limit"] = 25

if "_users_q" not in st.session_state:
    st.session_state["_users_q"] = ""

def load_page():
    cursor = st.session_state["_users_cursor"]
    limit = st.session_state["_users_limit"]
    q = st.session_state["_users_q"].strip()

    # Build query string
    qs = f"/admin/users?limit={limit}"
    if cursor:
        qs += f"&cursor={cursor}"
    if q:
        from urllib.parse import quote
        qs += f"&q={quote(q)}"

    data = api("GET", qs)

    st.session_state["_users_items"] = data.get("items", [])
    st.session_state["_users_next_cursor"] = data.get("next_cursor")

if "_users_items" not in st.session_state:
    load_page()

with st.sidebar:
    st.subheader("Filters / Paging")

    new_q = st.text_input("Search email contains", value=st.session_state["_users_q"])
    if st.button("Apply Filter"):
        st.session_state["_users_q"] = new_q
        st.session_state["_users_cursor"] = None
        st.session_state["_users_prev_stack"] = []
        load_page()
        st.experimental_rerun() if hasattr(st, "experimental_rerun") else st.rerun()

    st.markdown("---")

    st.write("Page size")
    new_limit = st.number_input("Limit", min_value=5, max_value=100, step=5, value=st.session_state["_users_limit"])
    if new_limit != st.session_state["_users_limit"]:
        st.session_state["_users_limit"] = int(new_limit)
        st.session_state["_users_cursor"] = None
        st.session_state["_users_prev_stack"] = []
        load_page()
        st.experimental_rerun() if hasattr(st, "experimental_rerun") else st.rerun()

    st.markdown("---")

    can_go_back = len(st.session_state["_users_prev_stack"]) > 0
    can_go_next = st.session_state.get("_users_next_cursor") is not None

    col_a, col_b = st.columns(2)
    with col_a:
        if st.button("← Prev", disabled=not can_go_back):
            prev_stack = st.session_state["_users_prev_stack"]
            st.session_state["_users_cursor"] = prev_stack.pop() if prev_stack else None
            load_page()
            st.experimental_rerun() if hasattr(st, "experimental_rerun") else st.rerun()
    with col_b:
        if st.button("Next →", disabled=not can_go_next):
            cur_cursor = st.session_state["_users_cursor"]
            st.session_state["_users_prev_stack"].append(cur_cursor if cur_cursor else "")
            st.session_state["_users_cursor"] = st.session_state["_users_next_cursor"]
            load_page()
            st.experimental_rerun() if hasattr(st, "experimental_rerun") else st.rerun()

    st.caption(f"Current cursor: {st.session_state['_users_cursor'] or '(start)'}")
    st.caption(f"Next cursor: {st.session_state.get('_users_next_cursor') or '(none)'}")

st.subheader("All Users")

items = st.session_state.get("_users_items", [])

if not items:
    st.info("No users found for this page / filter.")
else:
    import pandas as pd

    def ts_to_local(ts):
        if ts is None:
            return ""
        try:
            if hasattr(ts, "timestamp"):
                return datetime.fromtimestamp(ts.timestamp()).strftime("%Y-%m-%d %H:%M")
            # already datetime?
            if isinstance(ts, datetime):
                return ts.strftime("%Y-%m-%d %H:%M")
        except Exception:
            return str(ts)
        return str(ts)

    rows_for_df = []
    for u in items:
        rows_for_df.append({
            "uid": u.get("id", ""),
            "email": u.get("email", ""),
            "displayName": u.get("displayName", ""),
            "roles": ", ".join(u.get("roles", [])),
            "locale": u.get("locale", "en"),
            "createdAt": ts_to_local(u.get("createdAt")),
            "lastActiveAt": ts_to_local(u.get("lastActiveAt")),
        })

    df = pd.DataFrame(rows_for_df, columns=[
        "uid", "email", "displayName", "roles", "locale", "createdAt", "lastActiveAt"
    ])

    st.dataframe(
        df,
        use_container_width=True,
        height=360,
    )

st.markdown("---")

st.subheader("Create New User")

if not require_role_ui("admin"):
    st.info("Only admins can create new users.")
else:
    with st.form("create_user_form"):
        col1, col2 = st.columns(2)
        with col1:
            new_email = st.text_input("Email")
            new_pass = st.text_input("Temp Password", type="password")
            new_name = st.text_input("Display Name")
        with col2:
            st.caption("Assign roles to the new user:")
            want_admin = st.checkbox("admin", value=False)
            want_editor = st.checkbox("content_editor", value=False)
            want_instructor = st.checkbox("instructor", value=False)

        created = st.form_submit_button("Create User")

    if created:
        roles_list = []
        if want_admin:
            roles_list.append("admin")
        if want_editor:
            roles_list.append("content_editor")
        if want_instructor:
            roles_list.append("instructor")

        if not new_email or not new_pass:
            st.error("Email and password are required.")
        else:
            try:
                payload = {
                    "email": new_email.strip(),
                    "password": new_pass,
                    "displayName": new_name.strip() if new_name else None,
                    "roles": roles_list,
                }
                out = api("POST", "/admin/users", json=payload)
                st.success(f"User created: {out.get('email')} ({out.get('id')})")

                st.session_state["_users_cursor"] = None
                st.session_state["_users_prev_stack"] = []
                load_page()
                st.experimental_rerun() if hasattr(st, "experimental_rerun") else st.rerun()
            except Exception as e:
                st.error(str(e))

st.markdown("---")

with st.expander("Session / Debug", expanded=False):
    st.write("Your roles:", current_roles())
    st.write("Paging state:", {
        "cursor": st.session_state["_users_cursor"],
        "next_cursor": st.session_state.get("_users_next_cursor"),
        "prev_stack": st.session_state["_users_prev_stack"],
        "q": st.session_state["_users_q"],
        "limit": st.session_state["_users_limit"],
    })
    st.write("Items on this page:", len(items))
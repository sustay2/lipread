import streamlit as st
from utils.auth import ensure_login_ui, sign_out
from utils.firebase_rest import update_profile, change_password

st.set_page_config(page_title="Profile", page_icon="👤", layout="wide")
user = ensure_login_ui()

st.title("👤 Profile")

email = user.get("email")
uid = user.get("uid")
st.write(f"**UID:** `{uid}`")
st.write(f"**Email:** {email}")

st.markdown("### Update display name / photo")
with st.form("profile_basic"):
    new_name = st.text_input("Display name")
    new_photo = st.text_input("Photo URL")
    submit_basic = st.form_submit_button("Save")

if submit_basic:
    try:
        resp = update_profile(st.session_state["id_token"], display_name=new_name or None, photo_url=new_photo or None)
        st.success("Profile updated.")
    except Exception as e:
        st.error(f"Update failed: {e}")

st.markdown("---")
st.markdown("### Change password")
with st.form("profile_pw"):
    new_pw = st.text_input("New password", type="password")
    new_pw2 = st.text_input("Confirm new password", type="password")
    submit_pw = st.form_submit_button("Change")

if submit_pw:
    if not new_pw or new_pw != new_pw2:
        st.error("Passwords do not match.")
    else:
        try:
            j = change_password(st.session_state["id_token"], new_pw)
            
            from utils.auth import _save_session
            j["email"] = email
            _save_session(j)
            st.success("Password changed.")
        except Exception as e:
            st.error(f"Change failed: {e}")

st.markdown("---")
if st.button("Sign out"):
    sign_out()
    st.success("Signed out.")
    st.rerun()
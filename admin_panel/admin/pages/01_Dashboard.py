import streamlit as st
from utils.auth import ensure_login_ui, current_roles, require_role_ui
from utils.api import api

st.set_page_config(page_title="Dashboard", page_icon="📊", layout="wide")
user = ensure_login_ui()

st.title("📊 Admin Dashboard")

cols = st.columns(3)
with cols[0]:
    st.metric("Logged in as", user.get("email", ""))
with cols[1]:
    st.metric("Roles", ", ".join(current_roles()))
with cols[2]:
    st.metric("Access Level", "Admin Panel")

st.divider()

# Quick statistics
st.subheader("System Overview")
try:
    users = api("GET", "/admin/users")
    courses = api("GET", "/admin/courses")
    videos = api("GET", "/admin/videos")
    st.write("✅ Data loaded successfully.")

    col1, col2, col3 = st.columns(3)
    col1.metric("Total Users", len(users))
    col2.metric("Total Courses", len(courses))
    col3.metric("Total Videos", len(videos))
except Exception as e:
    st.warning(f"Could not fetch data: {e}")

st.divider()

# Quick links
st.subheader("Quick Links")
colA, colB, colC = st.columns(3)
colA.page_link("pages/02_Users_and_Roles.py", label="👤 Manage Users", icon="👤")
colB.page_link("pages/03_Courses.py", label="📚 Manage Courses", icon="📚")
colC.page_link("pages/06_Media_Library.py", label="🎞 Media Library", icon="🎞")

st.divider()
st.info("Use the sidebar to access more management pages.")
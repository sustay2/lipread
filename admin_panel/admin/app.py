import streamlit as st
from utils.auth import ensure_login_ui, current_roles

st.set_page_config(page_title="Admin Console", page_icon="🛠", layout="wide")
user = ensure_login_ui()

st.sidebar.title("Admin Console")
st.sidebar.write("Signed in as:", user.get("email"))
st.sidebar.write("Roles:", ", ".join(current_roles()) or "—")

st.write("Welcome! Use the pages in the left sidebar.")
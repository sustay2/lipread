import json
import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui
from utils.api import api

st.set_page_config(page_title="Viseme Sets", page_icon="👄", layout="wide")
user = ensure_login_ui()

st.title("👄 Viseme Sets")

def refresh_visemes():
    try:
        # we first try without language filter
        resp = api("GET", "/admin/visemes")
        # backend returns { "items": [...], "next_cursor": ... }
        items = resp.get("items", []) if isinstance(resp, dict) else []
        st.session_state["_visemes_cache"] = items
        st.success("Reloaded viseme sets.")
    except Exception as e:
        st.error(f"Failed to load viseme sets: {e}")

if "_visemes_cache" not in st.session_state:
    st.session_state["_visemes_cache"] = []
    refresh_visemes()

col_left, col_right = st.columns([1,1])
with col_left:
    st.subheader("All Defined Viseme Sets")

with col_right:
    if st.button("↻ Refresh", use_container_width=True):
        refresh_visemes()

visemes_list = st.session_state["_visemes_cache"]


if not visemes_list:
    st.info("No viseme sets found.")
else:
    for vs in visemes_list:
        vid = vs.get("id", "(no-id)")
        vname = vs.get("name", "(unnamed)")
        vlang = vs.get("language", "en")
        vmap = vs.get("mapping", {})
        vrefs = vs.get("references", [])

        with st.expander(f"{vname} [{vlang}] · {vid}", expanded=False):
            st.write("**ID:**", vid)
            st.write("**Language:**", vlang)

            st.write("**References:**")
            if vrefs:
                for ref in vrefs:
                    st.markdown(f"- {ref}")
            else:
                st.write("_none_")

            st.write("**Mapping (viseme → phoneme/group list):**")
            if isinstance(vmap, dict) and vmap:
                st.code(
                    json.dumps(vmap, indent=2, ensure_ascii=False),
                    language="json"
                )
            else:
                st.write("_empty mapping_")


if require_role_ui("admin", "content_editor"):
    st.markdown("---")
    st.subheader("Create New Viseme Set")

    with st.form("create_viseme_form"):
        new_name = st.text_input("Viseme Set Name", placeholder="Basic English Mouth Shapes")
        new_language = st.text_input("Language code", value="en")

        st.caption("Mapping: A JSON object where each viseme key maps to list of mouth/phoneme labels.")
        mapping_raw = st.text_area(
            "Mapping JSON",
            value='{\n  "P_B_M": ["p","b","m"],\n  "F_V": ["f","v"],\n  "AA": ["a","ah","aa"]\n}',
            height=160,
        )

        refs_raw = st.text_area(
            "References (one per line)",
            value="Dataset: GRID\nPaper: SomeLipReadingStudy2021",
            height=80
        )

        submitted = st.form_submit_button("Create Viseme Set")

    if submitted:
        try:
            try:
                mapping_obj = json.loads(mapping_raw)
                if not isinstance(mapping_obj, dict):
                    raise ValueError("Mapping must be a JSON object {viseme_key: [...]}")

            except Exception as je:
                st.error(f"Mapping JSON invalid: {je}")
                st.stop()

            refs_list = [line.strip() for line in refs_raw.splitlines() if line.strip()]

            payload = {
                "name": new_name.strip(),
                "language": new_language.strip() or "en",
                "mapping": mapping_obj,
                "references": refs_list,
            }

            created = api("POST", "/admin/visemes", json=payload)

            st.success(f"Created viseme set {created.get('id')}")

            refresh_visemes()

        except Exception as e:
            st.error(f"Failed to create viseme set: {e}")
else:
    st.info("You need admin or content_editor to create new viseme sets.")

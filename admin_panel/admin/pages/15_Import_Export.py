import io
import json
import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui
from utils.api import api

st.set_page_config(page_title="Import / Export (Firestore)", page_icon="📦", layout="wide")
user = ensure_login_ui()
st.title("📦 Firestore Import / Export")

if not require_role_ui("admin", "content_editor"):
    st.info("Admins or content editors only.")
    st.stop()

# ---------------- Export ----------------
st.header("Export")
with st.form("export_form"):
    c1, c2, c3 = st.columns(3)
    with c1:
        collection = st.text_input("Collection (top-level)*", placeholder="question_banks")
    with c2:
        where_field = st.text_input("Filter field (optional)", placeholder="topic")
    with c3:
        where_value = st.text_input("Filter value (optional)", placeholder="grammar")

    c4, c5, c6 = st.columns(3)
    with c4:
        limit = st.number_input("Limit (optional)", min_value=0, value=0, step=100)
    with c5:
        fmt = st.selectbox("Format", ["json", "ndjson"], index=0)
    with c6:
        pretty = st.checkbox("Pretty JSON", value=True)

    exp_go = st.form_submit_button("Export")

if exp_go:
    if not collection.strip():
        st.error("Collection is required.")
    else:
        params = {"collection": collection.strip(), "format": fmt, "pretty": pretty}
        if where_field.strip() and where_value.strip():
            params["where_field"] = where_field.strip()
            params["where_value"] = where_value.strip()
        if limit and limit > 0:
            params["limit"] = int(limit)

        data = api("GET", "/admin/firestore/export", params=params)
        if fmt == "json":
            blob = json.dumps(data, ensure_ascii=False, indent=2 if pretty else None).encode("utf-8")
            st.download_button(
                "Download export.json",
                data=io.BytesIO(blob),
                file_name=f"{collection}_export.json",
                mime="application/json",
            )
            st.code(blob.decode("utf-8")[:2000] + ("\n...truncated..." if len(blob) > 2000 else ""), language="json")
        else:
            # our API returns {"ndjson":[lines...]}
            lines = data.get("ndjson", [])
            nd = "\n".join(lines)
            st.download_button(
                "Download export.ndjson",
                data=io.BytesIO(nd.encode("utf-8")),
                file_name=f"{collection}_export.ndjson",
                mime="application/x-ndjson",
            )
            st.code(nd[:2000] + ("\n...truncated..." if len(nd) > 2000 else ""), language="json")

st.divider()

# ---------------- Import ----------------
st.header("Import")
with st.form("import_form"):
    c1, c2, c3 = st.columns(3)
    with c1:
        im_collection = st.text_input("Collection (top-level)*", placeholder="question_banks")
    with c2:
        mode = st.selectbox("Mode", ["append", "merge", "replace"], index=0,
                            help="append = insert/overwrite by id; merge = merge fields; replace = delete all then insert")
    with c3:
        preserve_ids = st.checkbox("Preserve _id from file", value=True,
                                   help="If unchecked, new auto-IDs will be generated.")

    up = st.file_uploader("Upload JSON or NDJSON exported by this tool", type=["json", "ndjson"])
    run = st.form_submit_button("Import")

if run:
    if not im_collection.strip():
        st.error("Collection is required.")
    elif not up:
        st.error("Please upload a file.")
    else:
        files = {"file": (up.name, up.getvalue(), "application/json")}
        params = {"collection": im_collection.strip(), "mode": mode, "preserve_ids": str(preserve_ids).lower()}
        res = api("POST", "/admin/firestore/import", params=params, files=files, data={})
        st.success(f"Imported to '{im_collection}': written={res.get('written',0)}, deleted={res.get('deleted',0)} (mode={res.get('mode')})")
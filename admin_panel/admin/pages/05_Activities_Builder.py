import streamlit as st
from utils.auth import ensure_login_ui, require_role_ui
from utils.api import api

st.set_page_config(page_title="Activities Builder", page_icon="🧪", layout="wide")
user = ensure_login_ui()

st.title("🧪 Activities Builder")

@st.cache_data(ttl=30.0)
def load_courses():
    try:
        data = api("GET", "/admin/courses")
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        return []
    except Exception as e:
        st.error(f"Failed to load courses: {e}")
        return []

@st.cache_data(ttl=30.0)
def load_modules(course_id: str):
    if not course_id:
        return []
    try:
        data = api("GET", f"/admin/modules?courseId={course_id}")
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        return []
    except Exception:
        return []

@st.cache_data(ttl=30.0)
def load_lessons(course_id: str, module_id: str):
    if not (course_id and module_id):
        return []
    try:
        data = api("GET", f"/admin/lessons?courseId={course_id}&moduleId={module_id}")
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        return []
    except Exception:
        return []

@st.cache_data(ttl=15.0)
def load_activities(course_id: str, module_id: str, lesson_id: str):
    if not (course_id and module_id and lesson_id):
        return []
    try:
        data = api("GET", f"/admin/activities?courseId={course_id}&moduleId={module_id}&lessonId={lesson_id}")
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        return []
    except Exception:
        return []

@st.cache_data(ttl=15.0)
def load_media_items():
    try:
        data = api("GET", "/admin/media?limit=200")
        items = data.get("items", []) if isinstance(data, dict) else (data or [])
        out = []
        for it in items:
            out.append({
                "id": it.get("id") or it.get("docId"),
                "label": it.get("title") or it.get("path") or it.get("storagePath"),
                "videoId": it.get("videoId") or it.get("id"),
                "path": it.get("path") or it.get("storagePath"),
            })
        if out:
            return out
    except Exception:
        pass

    try:
        vdata = api("GET", "/admin/videos?limit=200")
        vitems = vdata.get("items", []) if isinstance(vdata, dict) else (vdata or [])
        out = []
        for v in vitems:
            out.append({
                "id": v.get("id"),
                "label": v.get("title") or v.get("storagePath") or v.get("path"),
                "videoId": v.get("id"),
                "path": v.get("storagePath") or v.get("path"),
            })
        return out
    except Exception:
        return []

def load_viseme_sets():
    try:
        vs = api("GET", "/admin/visemes")
        if isinstance(vs, dict) and "items" in vs:
            vs = vs["items"]
        return vs
    except Exception:
        return []

def load_question_banks():
    try:
        data = api("GET", "/admin/question_banks")
        if isinstance(data, list):
            return data
        return data.get("items", [])
    except Exception as e:
        st.error(f"Failed to load question banks: {e}")
        return []

courses = load_courses()

course_labels = ["< choose course >"]
course_ids = [None]
for c in courses:
    cid = c.get("id")
    ctitle = c.get("title") or f"(untitled {cid})"
    corder = c.get("order", 0)
    course_labels.append(f"{corder} · {ctitle}")
    course_ids.append(cid)

ci_default = st.session_state.get("ab_course_idx", 0)
ci = st.selectbox(
    "Course",
    options=list(range(len(course_ids))),
    format_func=lambda i: course_labels[i],
    index=min(ci_default, len(course_ids)-1),
    key="ab_course_idx",
)
course_id = course_ids[ci]

modules = load_modules(course_id) if course_id else []
module_labels = ["< choose module >"]
module_ids = [None]
for m in modules:
    mid = m.get("id")
    mtitle = m.get("title") or f"(untitled {mid})"
    morder = m.get("order", 0)
    module_labels.append(f"{morder} · {mtitle}")
    module_ids.append(mid)

mi_default = st.session_state.get("ab_module_idx", 0)
mi = st.selectbox(
    "Module",
    options=list(range(len(module_ids))),
    format_func=lambda i: module_labels[i],
    index=min(mi_default, len(module_ids)-1),
    key="ab_module_idx",
)
module_id = module_ids[mi]

lessons = load_lessons(course_id, module_id) if (course_id and module_id) else []
lesson_labels = ["< choose lesson >"]
lesson_ids = [None]
for l in lessons:
    lid = l.get("id")
    ltitle = l.get("title") or f"(untitled {lid})"
    lorder = l.get("order", 0)
    lesson_labels.append(f"{lorder} · {ltitle}")
    lesson_ids.append(lid)

li_default = st.session_state.get("ab_lesson_idx", 0)
li = st.selectbox(
    "Lesson",
    options=list(range(len(lesson_ids))),
    format_func=lambda i: lesson_labels[i],
    index=min(li_default, len(lesson_ids)-1),
    key="ab_lesson_idx",
)
lesson_id = lesson_ids[li]

st.markdown("---")
st.header("Existing Activities in Lesson")

if course_id and module_id and lesson_id:
    acts = load_activities(course_id, module_id, lesson_id)
    if not acts:
        st.info("No activities yet.")
    else:
        header = st.columns([6, 2, 3, 3, 2, 2, 2])
        with header[0]: st.caption("Title")
        with header[1]: st.caption("Type")
        with header[2]: st.caption("Variant")
        with header[3]: st.caption("Order")
        with header[4]: st.caption("")
        with header[5]: st.caption("")
        with header[6]: st.caption("Actions")

        ids = [a.get("id") for a in acts]
        for i, a in enumerate(acts):
            cols = st.columns([6, 2, 3, 3, 2, 2, 2])
            with cols[0]:
                st.write(a.get("title") or "(untitled)")
            with cols[1]:
                st.write(a.get("type"))
            with cols[2]:
                st.caption(a.get("abVariant") or "—")
            with cols[3]:
                st.write(a.get("order", i))
            with cols[4]:
                if st.button("⬆️", key=f"act_up_{a['id']}", disabled=(i == 0)):
                    ids[i-1], ids[i] = ids[i], ids[i-1]
                    api(
                        "POST",
                        f"/admin/activities/reorder?courseId={course_id}&moduleId={module_id}&lessonId={lesson_id}",
                        json={"ids": ids},
                    )
                    st.cache_data.clear()
                    st.rerun()
            with cols[5]:
                if st.button("⬇️", key=f"act_dn_{a['id']}", disabled=(i == len(acts)-1)):
                    ids[i+1], ids[i] = ids[i], ids[i+1]
                    api(
                        "POST",
                        f"/admin/activities/reorder?courseId={course_id}&moduleId={module_id}&lessonId={lesson_id}",
                        json={"ids": ids},
                    )
                    st.cache_data.clear()
                    st.rerun()
            with cols[6]:
                with st.popover("⋯", use_container_width=True):
                    st.markdown("**Preview**")
                    st.caption(f"ID: {a.get('id')}")
                    st.json({"config": a.get("config", {}), "scoring": a.get("scoring", {})})
                    st.markdown("---")
                    if st.button("Duplicate", key=f"act_dup_{a['id']}"):
                        api("POST", f"/admin/activities/{a['id']}:duplicate", json={})
                        st.success("Duplicated.")
                        st.cache_data.clear()
                        st.rerun()
                    if require_role_ui("admin") and st.button("Delete", key=f"act_del_{a['id']}", type="secondary"):
                        api("DELETE", f"/admin/activities/{a['id']}")
                        st.cache_data.clear()
                        st.rerun()
else:
    st.info("Select course → module → lesson to view activities.")

st.markdown("---")
st.header("➕ Create New Activity")

if not (course_id and module_id and lesson_id):
    st.info("Select course → module → lesson first.")
    if not require_role_ui("admin", "content_editor"):
        st.stop()
else:
    activity_type = st.selectbox(
        "Activity type",
        [
            "video_drill",
            "viseme_match",
            "mirror_practice",
            "quiz",
            "practice_lip",
            "dictation",
        ],
        help=(
            "video_drill = watch/loop clip\n"
            "viseme_match = match mouth shapes to expected sequence\n"
            "mirror_practice = camera overlay practice\n"
            "quiz = MCQ/grammar-style questions\n"
            "practice_lip = mimic a target lip sequence on video\n"
            "dictation = type what you hear"
        ),
        key="activity_type_select",
    )

    with st.form("create_activity_form"):
        colA, colB = st.columns(2)
        with colA:
            title_val = st.text_input("Activity Title (shown to learner)")
            order_val = st.number_input("Order in lesson", value=0, step=1)

            st.subheader("Scoring / Thresholds")
            pass_threshold = st.number_input("Pass score (%)", value=70, step=1)
            gold_threshold = st.number_input("Gold score (%)", value=90, step=1)

        config = {}
        scoring_weights = {}
        ab_variant_val = ""

        with colB:
            st.subheader("A/B Variant (optional)")
            ab_variant_val = st.text_input("abVariant", value="")

            # ---- video_drill ----
            if activity_type == "video_drill":
                st.markdown("#### Video Drill Config")
                media_items = load_media_items()
                if media_items:
                    opts = [f"{m['label']} [{m['id']}]" for m in media_items]
                    idx = st.selectbox(
                        "Video Asset",
                        options=list(range(len(media_items))),
                        format_func=lambda i: opts[i],
                        key="video_drill_media_select"
                    )
                    video_id_val = media_items[idx]["id"]
                else:
                    st.warning("No media found. Upload in Media Library first.")
                    video_id_val = None

                caption_track_id_val = st.text_input("captionTrackId (optional)")
                loop_start_val = st.number_input("Loop Start (sec)", value=0.0, step=0.1)
                loop_end_val = st.number_input("Loop End (sec)", value=2.0, step=0.1)
                playback_rate_val = st.number_input("Playback Rate", value=1.0, step=0.1)

                config = {
                    "captionTrackId": caption_track_id_val.strip() or None,
                    "loopSection": [loop_start_val, loop_end_val],
                    "playbackRate": float(playback_rate_val),
                    "videoId": video_id_val,
                }
                scoring_weights = {}

            # ---- viseme_match ----
            elif activity_type == "viseme_match":
                st.markdown("#### Viseme Match Config")
                viseme_sets = load_viseme_sets()
                if viseme_sets:
                    vs_labels = [f"{vs.get('name','(no name)')} [{vs.get('id')}]" for vs in viseme_sets]
                    vs_idx = st.selectbox(
                        "Viseme Set",
                        options=list(range(len(viseme_sets))),
                        format_func=lambda i: vs_labels[i],
                        key="viseme_match_set_select"
                    )
                    viseme_set_id_val = viseme_sets[vs_idx]["id"]
                else:
                    st.warning("No viseme sets available.")
                    viseme_set_id_val = None

                expected_sequence_raw = st.text_input(
                    "Expected sequence (comma-separated viseme keys)",
                    help="e.g. P_B_M, AA, F_V"
                )
                tolerance_ms_val = st.number_input("toleranceMs", value=120, step=10)

                config = {
                    "visemeSetId": viseme_set_id_val,
                    "expected": [x.strip() for x in expected_sequence_raw.split(",") if x.strip()],
                    "toleranceMs": int(tolerance_ms_val),
                }
                scoring_weights = {
                    "timing": st.number_input("Weight: timing", value=0.4, step=0.1),
                    "shape": st.number_input("Weight: shape", value=0.6, step=0.1),
                }

            # ---- mirror_practice ----
            elif activity_type == "mirror_practice":
                st.markdown("#### Mirror Practice Config")
                roi_val = st.selectbox(
                    "ROI (region of interest)",
                    ["mouth", "lower-face", "full-face"],
                    index=0,
                    key="mirror_roi_select"
                )
                overlay_guides_val = st.checkbox(
                    "Show Overlay Guides",
                    value=True,
                    key="mirror_overlay_checkbox"
                )
                config = {
                    "roi": roi_val,
                    "overlayGuides": bool(overlay_guides_val),
                }
                scoring_weights = {
                    "clarity": st.number_input("Weight: clarity", value=0.3, step=0.1),
                    "consistency": st.number_input("Weight: consistency", value=0.3, step=0.1),
                    "timing": st.number_input("Weight: timing", value=0.4, step=0.1),
                }

            # ---- quiz ----
            elif activity_type == "quiz":
                st.markdown("#### Quiz Config")
                qbanks = load_question_banks()
                selected_bank_id = None
                if not qbanks:
                    st.warning("No question banks found. Create one in 'Question Banks' first.")
                else:
                    bank_labels = [
                        f"(lvl {b.get('difficulty',0)}) {b.get('title','(untitled)')} [{b.get('id','')}]"
                        for b in qbanks
                    ]
                    selected_bank_idx = st.selectbox(
                        "Question Bank",
                        options=list(range(len(qbanks))),
                        format_func=lambda i: bank_labels[i],
                        key="quiz_bank_select",
                    )
                    selected_bank_id = qbanks[selected_bank_idx].get("id")

                num_questions = st.number_input("numQuestions", min_value=1, max_value=50, value=5, step=1)

                config = {
                    "bankId": selected_bank_id,
                    "numQuestions": int(num_questions),
                }
                scoring_weights = {"score": 1.0}

            # ---- practice_lip ----
            elif activity_type == "practice_lip":
                st.markdown("#### Practice Lip Config")
                media = load_media_items()
                if not media:
                    st.warning("No media/videos found. Upload in **Media** first.")
                else:
                    labels = [f"{m['label']}  [{m['videoId'] or m['id']}]" for m in media]
                    idxs = list(range(len(media)))
                    sel = st.selectbox("Video", idxs, format_func=lambda i: labels[i], key="pl_media_idx")
                    chosen = media[sel]
                    use_video_id = st.toggle("Refer by videoId (off = use mediaPath)", value=True)
                    if use_video_id:
                        video_id_val = chosen.get("videoId") or chosen.get("id")
                        media_path_val = None
                    else:
                        video_id_val = None
                        media_path_val = chosen.get("path")

                expected = st.text_input("Expected word/phrase (text)", placeholder="e.g., 'bin', 'set blue at three'")
                expected_phones = st.text_input("Expected phones (optional, comma-separated)", placeholder="b, ih, n")

                visemes = load_viseme_sets()
                viseme_id = None
                if visemes:
                    v_labels = [f"{v.get('name','(untitled)')} [{v.get('id')}]" for v in visemes]
                    v_ids = [v.get("id") for v in visemes]
                    vidx = st.selectbox("Viseme set (optional)", options=list(range(len(v_ids))), format_func=lambda i: v_labels[i], key="pl_viseme_idx")
                    viseme_id = v_ids[vidx]

                c1, c2, c3 = st.columns(3)
                with c1:
                    cer_max = st.number_input("CER max (fail if >)", min_value=0.0, max_value=1.0, value=0.35, step=0.01)
                with c2:
                    wer_max = st.number_input("WER max (fail if >)", min_value=0.0, max_value=1.0, value=0.45, step=0.01)
                with c3:
                    viseme_min = st.number_input("Viseme score min (pass if ≥)", min_value=0.0, max_value=1.0, value=0.55, step=0.01)

                sw_cer = st.number_input("Weight: CER", min_value=0.0, max_value=5.0, value=0.4, step=0.1)
                sw_wer = st.number_input("Weight: WER", min_value=0.0, max_value=5.0, value=0.3, step=0.1)
                sw_vis = st.number_input("Weight: Viseme match", min_value=0.0, max_value=5.0, value=0.3, step=0.1)

                config = {
                    "videoId": video_id_val if 'video_id_val' in locals() else None,
                    "mediaPath": media_path_val if 'media_path_val' in locals() else None,
                    "expected": expected.strip() or None,
                    "expectedPhones": [p.strip() for p in expected_phones.split(",") if p.strip()],
                    "visemeSetId": viseme_id,
                    "thresholds": {
                        "cerMax": float(cer_max),
                        "werMax": float(wer_max),
                        "visemeScoreMin": float(viseme_min),
                    },
                }
                scoring_weights = {"cer": float(sw_cer), "wer": float(sw_wer), "viseme": float(sw_vis)}

            # ---- dictation ----
            elif activity_type == "dictation":
                st.markdown("#### Dictation Config")
                media = load_media_items()
                if not media:
                    st.warning("No media/videos found. Upload in **Media** first.")
                else:
                    labels = [f"{m['label']}  [{m['videoId'] or m['id']}]" for m in media]
                    idxs = list(range(len(media)))
                    sel = st.selectbox("Prompt media (audio/video)", idxs, format_func=lambda i: labels[i], key="dic_media_idx")
                    chosen = media[sel]
                    use_video_id = st.toggle("Refer by videoId (off = use mediaPath)", value=True, key="dic_use_vid")
                    if use_video_id:
                        video_id_val = chosen.get("videoId") or chosen.get("id")
                        media_path_val = None
                    else:
                        video_id_val = None
                        media_path_val = chosen.get("path")

                answers_csv = st.text_input("Acceptable answers (comma-separated, case-insensitive)", value="")
                answer_regex = st.text_input("Regex pattern (optional)", value="")
                max_chars = st.number_input("Max characters", min_value=10, max_value=300, value=80, step=5)

                sw_exact = st.number_input("Weight: exact/regex match", min_value=0.0, max_value=5.0, value=1.0, step=0.1)

                config = {
                    "videoId": video_id_val if 'video_id_val' in locals() else None,
                    "mediaPath": media_path_val if 'media_path_val' in locals() else None,
                    "answers": [x.strip() for x in answers_csv.split(",") if x.strip()],
                    "answerPattern": answer_regex.strip() or None,
                    "maxChars": int(max_chars),
                }
                scoring_weights = {"score": float(sw_exact)}

            submit_btn = st.form_submit_button("Create Activity")

        if submit_btn:
            if not title_val.strip():
                st.error("Title is required.")
            else:
                thresholds = {
                    "pass": int(pass_threshold),
                    "gold": int(gold_threshold),
                }
                payload = {
                    "type": activity_type,
                    "title": title_val.strip(),
                    "order": int(order_val),
                    "config": config,
                    "scoring": {
                        "weights": scoring_weights,
                        "thresholds": thresholds,
                        "feedback": {},
                    },
                    "abVariant": ab_variant_val.strip() if ab_variant_val else None,
                }
                try:
                    created = api(
                        "POST",
                        f"/admin/activities?courseId={course_id}&moduleId={module_id}&lessonId={lesson_id}",
                        json=payload,
                    )
                    st.success(f"Created activity {created.get('id')}")
                    st.cache_data.clear()
                    st.rerun()
                except Exception as e:
                    st.error(f"Failed to create activity: {e}")

if not require_role_ui("admin", "content_editor"):
    st.stop()
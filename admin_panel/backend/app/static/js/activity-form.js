(function () {
  /* --------------------------------------------------------
   * Small helpers
   * -------------------------------------------------------- */

  function safeArray(val) {
    if (Array.isArray(val)) return val;
    if (typeof val === "string" && val.trim()) {
      return val.split(",").map((v) => v.trim()).filter(Boolean);
    }
    return [];
  }

  function showError(el, message) {
    if (!el) return;
    let msg = el.parentElement.querySelector(".invalid-feedback");
    if (!msg) {
      msg = document.createElement("div");
      msg.className = "invalid-feedback";
      el.parentElement.appendChild(msg);
    }
    msg.textContent = message;
    el.classList.add("is-invalid");
  }

  function clearError(el) {
    if (!el) return;
    el.classList.remove("is-invalid");
    const msg = el.parentElement.querySelector(".invalid-feedback");
    if (msg) msg.textContent = "";
  }

  const difficultyToNumber = {
    beginner: 1,
    intermediate: 2,
    advanced: 3,
  };

  function difficultyFromValue(value) {
    if (typeof value === "string") return difficultyToNumber[value] || 1;
    if (typeof value === "number") {
      if (value >= 3) return difficultyToNumber.advanced;
      if (value >= 2) return difficultyToNumber.intermediate;
    }
    return difficultyToNumber.beginner;
  }

  function renderExistingMedia(inputEl, mediaId) {
    if (!inputEl) return;
    let helper =
      inputEl.parentElement.querySelector(".existing-media-note");
    if (!helper) {
      helper = document.createElement("div");
      helper.className = "form-text existing-media-note";
      inputEl.parentElement.appendChild(helper);
    }
    helper.textContent = mediaId
      ? `Current video: ${mediaId} (upload to replace)`
      : "";
    helper.classList.toggle("d-none", !mediaId);
  }

  /* --------------------------------------------------------
   * Main initializer
   * -------------------------------------------------------- */

  function initActivityForm(config) {
    const cfg = config || {};
    const initial = cfg.initialData || {};

    const form = document.getElementById("activityForm");
    const payloadInput = document.getElementById("activityPayload");

    if (!form || !payloadInput) return;

    const getEl = (name) =>
      form.querySelector(`[data-field="${name}"]`) ||
      form.elements[name] ||
      null;

    const readStr = (name, fallback = "") => {
      const el = getEl(name);
      const val = (el && el.value) || "";
      return (typeof val === "string" ? val : `${val || ""}`).trim() || fallback;
    };

    const readNum = (name, fallback = 0) => {
      const parsed = parseInt(readStr(name, ""), 10);
      return Number.isFinite(parsed) ? parsed : fallback;
    };

    const setValue = (name, value) => {
      const el = getEl(name);
      if (el) el.value = value ?? "";
    };

    const typeSelect = getEl("type");
    const difficultySelect = getEl("difficultyLevel");

    const sections = {
      quiz: document.getElementById("mcqSection"),
      dictation: document.getElementById("dictationSection"),
      practice_lip: document.getElementById("practiceSection"),
    };

    const questionList = document.getElementById("questionList");
    const dictationList = document.getElementById("dictationList");
    const practiceList = document.getElementById("practiceList");

    /* --------------------------------------------------------
     * REQUIRED FIX — ensure ONLY visible media inputs become required
     * -------------------------------------------------------- */

    function enforceMediaRequirements() {
      const type = typeSelect?.value || "quiz";

      // Remove required from ALL media inputs first (fixes browser errors)
      form.querySelectorAll(".question-media,.dictation-media,.practice-media")
        .forEach((el) => el.removeAttribute("required"));

      if (type === "quiz") {
        questionList.querySelectorAll(".mcq-question").forEach((card) => {
          const input = card.querySelector(".question-media");
          if (input && !card.dataset.existingMedia) {
            input.setAttribute("required", "required");
          }
        });
      } else if (type === "dictation") {
        dictationList.querySelectorAll(".dictation-item").forEach((card) => {
          const input = card.querySelector(".dictation-media");
          if (input && !card.dataset.existingMedia) {
            input.setAttribute("required", "required");
          }
        });
      } else if (type === "practice_lip") {
        practiceList.querySelectorAll(".practice-item").forEach((card) => {
          const input = card.querySelector(".practice-media");
          if (input && !card.dataset.existingMedia) {
            input.setAttribute("required", "required");
          }
        });
      }
    }

    function setSectionRequired(activeType) {
      form
        .querySelectorAll(
          ".question-stem, .option-text, .dictation-correct, .practice-description"
        )
        .forEach((el) => el.removeAttribute("required"));

      if (activeType === "quiz") {
        questionList
          .querySelectorAll(".question-stem, .option-text")
          .forEach((el) => el.setAttribute("required", "required"));
      } else if (activeType === "dictation") {
        dictationList
          .querySelectorAll(".dictation-correct")
          .forEach((el) => el.setAttribute("required", "required"));
      } else if (activeType === "practice_lip") {
        practiceList
          .querySelectorAll(".practice-description")
          .forEach((el) => el.setAttribute("required", "required"));
      }
    }

    function updateVisibility() {
      const type = typeSelect?.value || "quiz";
      Object.entries(sections).forEach(([key, el]) => {
        if (!el) return;
        el.classList.toggle("d-none", key !== type);
      });
      setSectionRequired(type);
      enforceMediaRequirements();
    }

    function renumber() {
      questionList
        .querySelectorAll(".question-index")
        .forEach((el, idx) => (el.textContent = idx + 1));
      dictationList
        .querySelectorAll(".dictation-index")
        .forEach((el, idx) => (el.textContent = idx + 1));
      practiceList
        .querySelectorAll(".practice-index")
        .forEach((el, idx) => (el.textContent = idx + 1));
    }

    /* ---------- options helpers (MCQ) ---------- */

    function ensureOptionGroup(card) {
      if (!card.dataset.optionGroup) {
        card.dataset.optionGroup = `q-${Date.now()}-${Math.random()
          .toString(36)
          .slice(2, 8)}`;
      }
      return card.dataset.optionGroup;
    }

    function updateOptionRemoveState(card) {
      const rows = card.querySelectorAll(".option-row");
      const disable = rows.length <= 2;
      rows.forEach((row) => {
        const btn = row.querySelector(".remove-option");
        if (btn) btn.disabled = disable;
      });
    }

    function addOptionRow(card, value, isCorrect) {
      const list = card.querySelector(".option-list");
      if (!list) return;

      const groupName = ensureOptionGroup(card);

      const row = document.createElement("div");
      row.className = "input-group option-row mb-2";

      const addon = document.createElement("div");
      addon.className = "input-group-text";

      const radio = document.createElement("input");
      radio.type = "radio";
      radio.className = "form-check-input mt-0 option-correct";
      radio.name = groupName;
      radio.title = "Mark as correct";
      radio.checked = Boolean(isCorrect);

      addon.appendChild(radio);

      const input = document.createElement("input");
      input.type = "text";
      input.className = "form-control option-text";
      input.name = "mcqOption";
      input.dataset.field = "optionText";
      input.placeholder = "Option text";
      if (value) input.value = value;

      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className = "btn btn-outline-danger remove-option";
      removeBtn.innerHTML = '<i class="bi bi-x"></i>';

      removeBtn.addEventListener("click", () => {
        const rows = card.querySelectorAll(".option-row");
        if (rows.length <= 2) return; // always keep at least 2
        row.remove();
        updateOptionRemoveState(card);
      });

      row.appendChild(addon);
      row.appendChild(input);
      row.appendChild(removeBtn);
      list.appendChild(row);

      updateOptionRemoveState(card);
    }

    function populateMcqCard(card, data) {
      const stemEl = card.querySelector(".question-stem");
      const explEl = card.querySelector(".question-explanation");
      if (data) {
        if (data.id) card.dataset.questionId = data.id;
        if (stemEl) stemEl.value = data.stem || "";
        if (explEl) explEl.value = data.explanation || "";
        const mediaInput = card.querySelector(".question-media");
        if (data.mediaId && mediaInput) {
          card.dataset.existingMedia = data.mediaId;
          renderExistingMedia(mediaInput, data.mediaId);
        }

        const opts =
          (Array.isArray(data.options) && data.options.length
            ? data.options
            : ["Option A", "Option B"]);
        const answerSet = new Set(safeArray(data.answers || []));
        const list = card.querySelector(".option-list");
        if (list) list.innerHTML = "";
        opts.forEach((opt, idx) => {
          const isCorrect =
            answerSet.has(opt) || (!answerSet.size && idx === 0);
          addOptionRow(card, opt, isCorrect);
        });
      } else {
        // New question: exactly 2 blank options
        const list = card.querySelector(".option-list");
        if (list) list.innerHTML = "";
        addOptionRow(card, "", true);
        addOptionRow(card, "", false);
      }

      updateOptionRemoveState(card);
    }

    /* ---------- add cards (MCQ / Dictation / Practice) ---------- */

    function addMcq(data) {
      const tpl = document.getElementById("mcqTemplate");
      if (!tpl || !questionList) return;
      const card = tpl.content.firstElementChild.cloneNode(true);

      const removeBtn = card.querySelector(".remove-question");
      if (removeBtn) {
        removeBtn.addEventListener("click", () => {
          card.remove();
          renumber();
          enforceMediaRequirements();
        });
      }

      const addOptionBtn = card.querySelector(".add-option");
      if (addOptionBtn) {
        addOptionBtn.addEventListener("click", () => {
          addOptionRow(card, "", false);
        });
      }

      populateMcqCard(card, data);

      questionList.appendChild(card);
      renumber();
      setSectionRequired(typeSelect?.value || "quiz");
      enforceMediaRequirements();
    }

    function addDictation(data) {
      const tpl = document.getElementById("dictationTemplate");
      if (!tpl || !dictationList) return;
      const card = tpl.content.firstElementChild.cloneNode(true);

      const removeBtn = card.querySelector(".remove-dictation");
      if (removeBtn) {
        removeBtn.addEventListener("click", () => {
          card.remove();
          renumber();
          enforceMediaRequirements();
        });
      }

      if (data) {
        card.dataset.itemId = data.id || "";
        const correctEl = card.querySelector(".dictation-correct");
        const hintsEl = card.querySelector(".dictation-hints");
        if (correctEl) correctEl.value = data.correctText || "";
        if (hintsEl) hintsEl.value = data.hints || "";
        const mediaInput = card.querySelector(".dictation-media");
        if (data.mediaId && mediaInput) {
          card.dataset.existingMedia = data.mediaId;
          renderExistingMedia(mediaInput, data.mediaId);
        }
      }

      dictationList.appendChild(card);
      renumber();
      setSectionRequired(typeSelect?.value || "quiz");
      enforceMediaRequirements();
    }

    function addPractice(data) {
      const tpl = document.getElementById("practiceTemplate");
      if (!tpl || !practiceList) return;
      const card = tpl.content.firstElementChild.cloneNode(true);

      const removeBtn = card.querySelector(".remove-practice");
      if (removeBtn) {
        removeBtn.addEventListener("click", () => {
          card.remove();
          renumber();
          enforceMediaRequirements();
        });
      }

      if (data) {
        card.dataset.itemId = data.id || "";
        const descEl = card.querySelector(".practice-description");
        const targetEl = card.querySelector(".practice-target");
        if (descEl) descEl.value = data.description || "";
        if (targetEl) targetEl.value = data.targetWord || "";
        const mediaInput = card.querySelector(".practice-media");
        if (data.mediaId && mediaInput) {
          card.dataset.existingMedia = data.mediaId;
          renderExistingMedia(mediaInput, data.mediaId);
        }
      }

      practiceList.appendChild(card);
      renumber();
      setSectionRequired(typeSelect?.value || "quiz");
      enforceMediaRequirements();
    }

    /* ---------- initial render ---------- */

    function renderInitialState() {
      const scoring = initial.scoring || {};
      const difficultyValue = difficultyFromValue(
        initial.difficultyLevel ?? initial.questionBank?.difficulty ?? 1
      );

      setValue("title", initial.title || "");
      setValue("type", initial.type || "quiz");
      setValue("order", initial.order ?? 0);

      if (difficultySelect) {
        const selected = Object.entries(difficultyToNumber).find(
          ([, num]) => num === difficultyValue
        );
        difficultySelect.value = (selected && selected[0]) || "beginner";
      }

      setValue("maxScore", scoring.maxScore ?? 100);
      setValue("passingScore", scoring.passingScore ?? 60);

      if (initial.questionBank) {
        setValue("bankTitle", initial.questionBank.title || "");
        setValue(
          "bankTags",
          safeArray(initial.questionBank.tags || []).join(",")
        );
        setValue("bankDescription", initial.questionBank.description || "");
      }

      const existingQuestions = initial.questions || [];
      const existingDictation = initial.dictationItems || [];
      const existingPractice = initial.practiceItems || [];

      const type = initial.type || "quiz";

      if (type === "quiz") {
        if (existingQuestions.length) {
          existingQuestions.forEach((q) => addMcq(q));
        } else {
          // default: one MCQ with 2 empty options
          addMcq();
        }
      }

      if (type === "dictation") {
        if (existingDictation.length) {
          existingDictation.forEach((d) => addDictation(d));
        } else {
          addDictation();
        }
      }

      if (type === "practice_lip") {
        if (existingPractice.length) {
          existingPractice.forEach((p) => addPractice(p));
        } else {
          addPractice();
        }
      }

      updateVisibility();
    }

    /* ---------- collectors for payload ---------- */

    function collectMcq() {
      const list = [];
      questionList
        .querySelectorAll(".mcq-question")
        .forEach((card, idx) => {
          const stemEl = card.querySelector(".question-stem");
          const stem = (stemEl?.value || "").trim();

          const optionInputs = card.querySelectorAll(".option-text");
          const options = [];
          optionInputs.forEach((inp) => {
            const val = inp.value.trim();
            if (val) options.push(val);
          });

          const correctRadio = card.querySelector(".option-correct:checked");
          let correctText = null;
          if (correctRadio) {
            const row = correctRadio.closest(".option-row");
            const optInput = row && row.querySelector(".option-text");
            correctText = (optInput?.value || "").trim();
          }

          const explEl =
            card.querySelector(".question-explanation") ||
            card.querySelector('[data-field="explanation"]');
          const explanation = (explEl?.value || "").trim();

          const mediaInput = card.querySelector(".question-media");
          const file = mediaInput && mediaInput.files[0];
          const existing = card.dataset.existingMedia || null;

          list.push({
            id: card.dataset.questionId || undefined,
            stem,
            options,
            answers: correctText ? [correctText] : [],
            explanation: explanation || undefined,
            type: "mcq",
            mediaId: existing || undefined,
            existingMediaId: existing || undefined,
            needsUpload: Boolean(file),
            mediaField:
              (mediaInput && mediaInput.getAttribute("name")) ||
              "questionMedia",
          });
        });
      return list;
    }

    function collectDictation() {
      const list = [];
      dictationList
        .querySelectorAll(".dictation-item")
        .forEach((card) => {
          const correctEl = card.querySelector(".dictation-correct");
          const hintsEl = card.querySelector(".dictation-hints");
          const correctText = (correctEl?.value || "").trim();
          const hints = (hintsEl?.value || "").trim();

          const mediaInput = card.querySelector(".dictation-media");
          const file = mediaInput && mediaInput.files[0];
          const existing = card.dataset.existingMedia || null;

          list.push({
            id: card.dataset.itemId || undefined,
            correctText,
            hints: hints || undefined,
            mediaId: existing || undefined,
            existingMediaId: existing || undefined,
            needsUpload: Boolean(file),
            mediaField:
              (mediaInput && mediaInput.getAttribute("name")) ||
              "dictationMedia",
          });
        });
      return list;
    }

    function collectPractice() {
      const list = [];
      practiceList
        .querySelectorAll(".practice-item")
        .forEach((card) => {
          const descEl = card.querySelector(".practice-description");
          const targetEl = card.querySelector(".practice-target");
          const description = (descEl?.value || "").trim();
          const targetWord = (targetEl?.value || "").trim();

          const mediaInput = card.querySelector(".practice-media");
          const file = mediaInput && mediaInput.files[0];
          const existing = card.dataset.existingMedia || null;

          list.push({
            id: card.dataset.itemId || undefined,
            description,
            targetWord: targetWord || undefined,
            mediaId: existing || undefined,
            existingMediaId: existing || undefined,
            needsUpload: Boolean(file),
            mediaField:
              (mediaInput && mediaInput.getAttribute("name")) ||
              "practiceMedia",
          });
        });
      return list;
    }

    /* ---------- validation ---------- */

    function validateForm() {
      let hasError = false;
      const type = typeSelect?.value || "quiz";

      const titleEl = getEl("title");
      clearError(titleEl);
      if (!readStr("title")) {
        showError(titleEl, "Title is required.");
        hasError = true;
      }

      if (type === "quiz") {
        const bankTitle = readStr("bankTitle");
        if (!bankTitle) {
            setValue("bankTitle", readStr("title") + " Bank");
        }

        const cards = questionList.querySelectorAll(".mcq-question");
        if (!cards.length) {
          alert("Add at least one MCQ question.");
          hasError = true;
        }

        cards.forEach((card, idx) => {
          const stemEl = card.querySelector(".question-stem");
          clearError(stemEl);
          const stem = (stemEl?.value || "").trim();
          if (!stem) {
            showError(
              stemEl,
              `Question ${idx + 1} is missing a question stem.`
            );
            hasError = true;
          }

          const optionInputs = card.querySelectorAll(".option-text");
          const options = [];
          optionInputs.forEach((inp) => {
            const val = inp.value.trim();
            if (val) options.push(val);
          });
          optionInputs.forEach((inp) => clearError(inp));

          if (options.length < 2) {
            const firstOpt = optionInputs[0];
            showError(
              firstOpt,
              `Question ${idx + 1} needs at least two options.`
            );
            hasError = true;
          }

          const correctRadio = card.querySelector(".option-correct:checked");
          if (!correctRadio) {
            const firstOpt = optionInputs[0];
            showError(
              firstOpt,
              `Please select the correct option for question ${idx + 1}.`
            );
            hasError = true;
          }

          const mediaInput = card.querySelector(".question-media");
          const file = mediaInput && mediaInput.files[0];
          const existing = card.dataset.existingMedia || null;
          clearError(mediaInput);
          if (!existing && !file) {
            showError(
              mediaInput,
              `Question ${idx + 1} must have a video uploaded.`
            );
            hasError = true;
          }
        });
      } else if (type === "dictation") {
        const cards = dictationList.querySelectorAll(".dictation-item");
        if (!cards.length) {
          alert("Add at least one dictation item.");
          hasError = true;
        }
        cards.forEach((card, idx) => {
          const textEl = card.querySelector(".dictation-correct");
          const mediaInput = card.querySelector(".dictation-media");
          const file = mediaInput && mediaInput.files[0];
          const existing = card.dataset.existingMedia || null;

          clearError(textEl);
          clearError(mediaInput);

          if (!textEl || !textEl.value.trim()) {
            showError(
              textEl,
              `Dictation item ${idx + 1} must have the correct text.`
            );
            hasError = true;
          }
          if (!existing && !file) {
            showError(
              mediaInput,
              `Dictation item ${idx + 1} must have a video.`
            );
            hasError = true;
          }
        });
      } else if (type === "practice_lip") {
        const cards = practiceList.querySelectorAll(".practice-item");
        if (!cards.length) {
          alert("Add at least one practice item.");
          hasError = true;
        }
        cards.forEach((card, idx) => {
          const descEl = card.querySelector(".practice-description");
          const mediaInput = card.querySelector(".practice-media");
          const file = mediaInput && mediaInput.files[0];
          const existing = card.dataset.existingMedia || null;

          clearError(descEl);
          clearError(mediaInput);

          if (!descEl || !descEl.value.trim()) {
            showError(
              descEl,
              `Practice item ${idx + 1} must have a description.`
            );
            hasError = true;
          }
          if (!existing && !file) {
            showError(
              mediaInput,
              `Practice item ${idx + 1} must have a video.`
            );
            hasError = true;
          }
        });
      }

      return !hasError;
    }

    /* ---------- submit handler ---------- */

    form.addEventListener("submit", (e) => {
      if (!validateForm()) {
        e.preventDefault();
        return;
      }

      const type = typeSelect?.value || "quiz";
      const selectedDifficulty =
        difficultySelect?.value || "beginner";

      const config = {
        ...(initial.config || {}),
        difficultyLevel: selectedDifficulty,
      };

      if (type === "quiz") {
        config.embedQuestions = true;
      }

      const payload = {
        title: readStr("title"),
        type,
        order: readNum("order", 0),
        difficultyLevel: selectedDifficulty,
        config,
        scoring: {
          maxScore: readNum("maxScore", 100),
          passingScore: readNum("passingScore", 60),
        },
      };

      if (type === "quiz") {
        payload.questionBank = {
          id: initial.questionBank?.id,
          title: readStr("bankTitle"),
          difficulty: difficultyFromValue(selectedDifficulty),
          tags: safeArray(readStr("bankTags")),
          description: readStr("bankDescription"),
        };
        payload.questions = collectMcq();
      } else if (type === "dictation") {
        payload.dictationItems = collectDictation();
      } else if (type === "practice_lip") {
        payload.practiceItems = collectPractice();
      }

      payloadInput.value = JSON.stringify(payload);
    });

    /* ---------- UI events ---------- */

    document
      .getElementById("addQuestionBtn")
      ?.addEventListener("click", () => addMcq());

    document
      .getElementById("addDictationBtn")
      ?.addEventListener("click", () => addDictation());

    document
      .getElementById("addPracticeBtn")
      ?.addEventListener("click", () => addPractice());

    typeSelect?.addEventListener("change", () => {
      const type = typeSelect.value || "quiz";
      // When switching type, ensure at least one card exists for that section
      if (type === "quiz" && !questionList.querySelector(".mcq-question")) {
        addMcq();
      }
      if (
        type === "dictation" &&
        !dictationList.querySelector(".dictation-item")
      ) {
        addDictation();
      }
      if (
        type === "practice_lip" &&
        !practiceList.querySelector(".practice-item")
      ) {
        addPractice();
      }
      updateVisibility();
    });

    /* ---------- kick things off ---------- */

    renderInitialState();
  }

  window.initActivityForm = initActivityForm;
})();
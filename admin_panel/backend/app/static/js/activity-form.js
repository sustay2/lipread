(function () {
  function safeArray(val) {
    if (Array.isArray(val)) return val;
    if (typeof val === 'string' && val.trim()) return val.split(',').map((v) => v.trim()).filter(Boolean);
    return [];
  }

  const difficultyToNumber = {
    beginner: 1,
    intermediate: 2,
    advanced: 3,
  };

  function difficultyFromValue(value) {
    if (typeof value === 'string') {
      return difficultyToNumber[value] || 1;
    }
    if (typeof value === 'number') {
      if (value >= 3) return difficultyToNumber.advanced;
      if (value >= 2) return difficultyToNumber.intermediate;
    }
    return difficultyToNumber.beginner;
  }

  function createExistingMediaNote(inputEl, mediaId) {
    if (!inputEl) return;
    let helper = inputEl.parentElement.querySelector('.existing-media-note');
    if (!helper) {
      helper = document.createElement('div');
      helper.className = 'form-text existing-media-note';
      inputEl.parentElement.appendChild(helper);
    }
    helper.textContent = mediaId ? `Current video: ${mediaId} (upload to replace)` : '';
    helper.classList.toggle('d-none', !mediaId);
  }

  function initActivityForm(config) {
    const cfg = config || {};
    const initial = cfg.initialData || {};

    const typeSelect = document.getElementById('activityType');
    const sections = {
      quiz: document.getElementById('mcqSection'),
      dictation: document.getElementById('dictationSection'),
      practice_lip: document.getElementById('practiceSection'),
    };

    const questionList = document.getElementById('questionList');
    const dictationList = document.getElementById('dictationList');
    const practiceList = document.getElementById('practiceList');

    function toggleRequired(selector, enabled) {
      document.querySelectorAll(selector).forEach((el) => {
        if (enabled) {
          el.setAttribute('required', 'required');
        } else {
          el.removeAttribute('required');
        }
      });
    }

    function enforceMediaRequirements() {
      const type = typeSelect.value;
      if (type === 'quiz') {
        document.querySelectorAll('#questionList .mcq-question').forEach((card) => {
          const input = card.querySelector('.question-media');
          if (!input) return;
          if (card.dataset.existingMedia) input.removeAttribute('required');
          else input.setAttribute('required', 'required');
        });
      } else if (type === 'dictation') {
        document.querySelectorAll('#dictationList .dictation-item').forEach((card) => {
          const input = card.querySelector('.dictation-media');
          if (!input) return;
          if (card.dataset.existingMedia) input.removeAttribute('required');
          else input.setAttribute('required', 'required');
        });
      } else if (type === 'practice_lip') {
        document.querySelectorAll('#practiceList .practice-item').forEach((card) => {
          const input = card.querySelector('.practice-media');
          if (!input) return;
          if (card.dataset.existingMedia) input.removeAttribute('required');
          else input.setAttribute('required', 'required');
        });
      }
    }

    function updateVisibility() {
      const type = typeSelect.value;
      Object.entries(sections).forEach(([key, el]) => {
        if (!el) return;
        el.classList.toggle('d-none', key !== type);
      });
      toggleRequired('.question-stem, .option-text', type === 'quiz');
      toggleRequired('.dictation-correct', type === 'dictation');
      toggleRequired('.practice-description', type === 'practice_lip');
      enforceMediaRequirements();
    }

    function renumber() {
      document.querySelectorAll('#questionList .mcq-question .question-index').forEach((el, idx) => (el.textContent = idx + 1));
      document.querySelectorAll('#dictationList .dictation-item .dictation-index').forEach((el, idx) => (el.textContent = idx + 1));
      document.querySelectorAll('#practiceList .practice-item .practice-index').forEach((el, idx) => (el.textContent = idx + 1));
    }

    function ensureOptionGroup(card) {
      if (!card.dataset.optionGroup) {
        card.dataset.optionGroup = `q-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      }
      return card.dataset.optionGroup;
    }

    function updateOptionRemoveState(card) {
      const rows = card.querySelectorAll('.option-row');
      const disable = rows.length <= 2;
      rows.forEach((row) => row.querySelector('.remove-option').toggleAttribute('disabled', disable));
    }

    function addOptionRow(card, value, isCorrect) {
      const list = card.querySelector('.option-list');
      if (!list) return;
      const groupName = ensureOptionGroup(card);
      const row = document.createElement('div');
      row.className = 'input-group option-row mb-2';
      const addon = document.createElement('div');
      addon.className = 'input-group-text';
      const radio = document.createElement('input');
      radio.type = 'radio';
      radio.name = groupName;
      radio.className = 'form-check-input mt-0 option-correct';
      radio.title = 'Mark as correct';
      radio.checked = Boolean(isCorrect);
      addon.appendChild(radio);
      const input = document.createElement('input');
      input.type = 'text';
      input.className = 'form-control option-text';
      input.placeholder = 'Option text';
      if (value) input.value = value;
      const removeBtn = document.createElement('button');
      removeBtn.type = 'button';
      removeBtn.className = 'btn btn-outline-danger remove-option';
      removeBtn.innerHTML = '<i class="bi bi-x"></i>';
      removeBtn.addEventListener('click', () => {
        if (card.querySelectorAll('.option-row').length <= 2) return;
        row.remove();
        updateOptionRemoveState(card);
      });
      row.appendChild(addon);
      row.appendChild(input);
      row.appendChild(removeBtn);
      list.appendChild(row);
      updateOptionRemoveState(card);
    }

    function populateOptions(card, options, answers) {
      const opts = Array.isArray(options) && options.length ? options : ['Option A', 'Option B'];
      const answerSet = new Set(safeArray(answers));
      const list = card.querySelector('.option-list');
      if (list) list.innerHTML = '';
      opts.forEach((opt, idx) => {
        const isCorrect = answerSet.has(opt) || (!answerSet.size && idx === 0);
        addOptionRow(card, opt, isCorrect);
      });
      if (card.querySelectorAll('.option-row').length < 2) {
        addOptionRow(card, '', false);
      }
      updateOptionRemoveState(card);
    }

    function populateQuestionCard(card, data) {
      const stem = data?.stem || '';
      const explanation = data?.explanation || '';
      if (stem) card.querySelector('.question-stem').value = stem;
      populateOptions(card, data?.options || [], data?.answers || []);
      if (explanation) card.querySelector('.question-explanation').value = explanation;
      if (data?.mediaId) {
        card.dataset.existingMedia = data.mediaId;
        createExistingMediaNote(card.querySelector('.question-media'), data.mediaId);
      }
      if (data?.id) {
        card.dataset.questionId = data.id;
      }
    }

    function populateDictationCard(card, data) {
      if (data?.correctText) card.querySelector('.dictation-correct').value = data.correctText;
      if (data?.hints) card.querySelector('.dictation-hints').value = data.hints;
      if (data?.mediaId) {
        card.dataset.existingMedia = data.mediaId;
        createExistingMediaNote(card.querySelector('.dictation-media'), data.mediaId);
      }
      if (data?.id) card.dataset.itemId = data.id;
    }

    function populatePracticeCard(card, data) {
      if (data?.description) card.querySelector('.practice-description').value = data.description;
      if (data?.targetWord) card.querySelector('.practice-target').value = data.targetWord;
      if (data?.mediaId) {
        card.dataset.existingMedia = data.mediaId;
        createExistingMediaNote(card.querySelector('.practice-media'), data.mediaId);
      }
      if (data?.id) card.dataset.itemId = data.id;
    }

    function addMcqQuestion(data) {
      const tpl = document.getElementById('mcqTemplate');
      const clone = tpl.content.firstElementChild.cloneNode(true);
      clone.querySelector('.remove-question').addEventListener('click', () => {
        clone.remove();
        renumber();
      });
      clone.querySelector('.add-option')?.addEventListener('click', () => {
        addOptionRow(clone, '', false);
      });
      questionList.appendChild(clone);
      populateQuestionCard(clone, data);
      enforceMediaRequirements();
      renumber();
    }

    function addDictationItem(data) {
      const tpl = document.getElementById('dictationTemplate');
      const clone = tpl.content.firstElementChild.cloneNode(true);
      clone.querySelector('.remove-dictation').addEventListener('click', () => {
        clone.remove();
        renumber();
      });
      dictationList.appendChild(clone);
      populateDictationCard(clone, data);
      enforceMediaRequirements();
      renumber();
    }

    function addPracticeItem(data) {
      const tpl = document.getElementById('practiceTemplate');
      const clone = tpl.content.firstElementChild.cloneNode(true);
      clone.querySelector('.remove-practice').addEventListener('click', () => {
        clone.remove();
        renumber();
      });
      practiceList.appendChild(clone);
      populatePracticeCard(clone, data);
      enforceMediaRequirements();
      renumber();
    }

    function collectMcqQuestions() {
      const questions = [];
      const issues = [];
      document.querySelectorAll('#questionList .mcq-question').forEach((card, idx) => {
        const stem = card.querySelector('.question-stem').value.trim();
        const optionRows = Array.from(card.querySelectorAll('.option-row'));
        const options = [];
        let correctAnswer = null;
        optionRows.forEach((row) => {
          const text = row.querySelector('.option-text').value.trim();
          const isCorrect = row.querySelector('.option-correct').checked;
          if (!text) return;
          options.push(text);
          if (isCorrect) correctAnswer = text;
        });
        if (!stem) {
          issues.push(`Question ${idx + 1} is missing a stem.`);
          return;
        }
        if (options.length < 2) {
          issues.push(`Question ${idx + 1} needs at least two options.`);
          return;
        }
        if (!correctAnswer) {
          issues.push(`Please select the correct option for question ${idx + 1}.`);
          return;
        }
        const explanation = card.querySelector('.question-explanation').value.trim();
        const mediaInput = card.querySelector('.question-media');
        const mediaFile = mediaInput.files[0];
        const existingMedia = card.dataset.existingMedia || null;
        questions.push({
          id: card.dataset.questionId || undefined,
          stem,
          options,
          answers: [correctAnswer],
          explanation: explanation || undefined,
          type: 'mcq',
          mediaId: existingMedia || undefined,
          needsUpload: Boolean(mediaFile),
        });
      });
      return { questions, issues };
    }

    function collectDictationItems() {
      const items = [];
      document.querySelectorAll('#dictationList .dictation-item').forEach((card) => {
        const correctText = card.querySelector('.dictation-correct').value.trim();
        const hints = card.querySelector('.dictation-hints').value.trim();
        const mediaInput = card.querySelector('.dictation-media');
        const mediaFile = mediaInput.files[0];
        const existingMedia = card.dataset.existingMedia || null;
        if (!correctText && !existingMedia && !mediaFile) return;
        items.push({
          id: card.dataset.itemId || undefined,
          correctText,
          hints: hints || undefined,
          mediaId: existingMedia || undefined,
          needsUpload: Boolean(mediaFile),
        });
      });
      return items;
    }

    function collectPracticeItems() {
      const items = [];
      document.querySelectorAll('#practiceList .practice-item').forEach((card) => {
        const description = card.querySelector('.practice-description').value.trim();
        const targetWord = card.querySelector('.practice-target').value.trim();
        const mediaInput = card.querySelector('.practice-media');
        const mediaFile = mediaInput.files[0];
        const existingMedia = card.dataset.existingMedia || null;
        if (!description && !existingMedia && !mediaFile) return;
        items.push({
          id: card.dataset.itemId || undefined,
          description,
          targetWord: targetWord || undefined,
          mediaId: existingMedia || undefined,
          needsUpload: Boolean(mediaFile),
        });
      });
      return items;
    }

    function renderInitialState() {
      const scoring = initial.scoring || {};
      const difficultySelect = document.getElementById('activityDifficulty');
      const difficultyValue = difficultyFromValue(initial.difficultyLevel ?? initial.questionBank?.difficulty ?? 1);
      document.getElementById('activityTitle').value = initial.title || '';
      document.getElementById('activityType').value = initial.type || 'quiz';
      document.getElementById('activityOrder').value = initial.order ?? 0;
      if (difficultySelect) {
        const selected = Object.entries(difficultyToNumber).find(([, num]) => num === difficultyValue);
        difficultySelect.value = (selected && selected[0]) || 'beginner';
      }
      document.getElementById('maxScore').value = scoring.maxScore ?? 100;
      document.getElementById('passingScore').value = scoring.passingScore ?? 60;

      if (initial.questionBank) {
        document.getElementById('bankTitle').value = initial.questionBank.title || '';
        document.getElementById('bankTags').value = safeArray(initial.questionBank.tags || []).join(',');
        document.getElementById('bankDescription').value = initial.questionBank.description || '';
      }

      const existingQuestions = initial.questions || [];
      if (existingQuestions.length) {
        existingQuestions.forEach((q) => addMcqQuestion(q));
      } else {
        addMcqQuestion();
      }

      const existingDictation = initial.dictationItems || [];
      if (existingDictation.length) existingDictation.forEach((d) => addDictationItem(d));
      else addDictationItem();

      const existingPractice = initial.practiceItems || [];
      if (existingPractice.length) existingPractice.forEach((p) => addPracticeItem(p));
      else addPracticeItem();

      updateVisibility();
    }

    document.getElementById('addQuestionBtn')?.addEventListener('click', () => addMcqQuestion());
    document.getElementById('addDictationBtn')?.addEventListener('click', () => addDictationItem());
    document.getElementById('addPracticeBtn')?.addEventListener('click', () => addPracticeItem());
    typeSelect?.addEventListener('change', updateVisibility);

    renderInitialState();

    const form = document.getElementById('activityForm');
    form?.addEventListener('submit', (e) => {
      const formData = new FormData(form);
      const type = formData.get('type') || typeSelect.value;
      const selectedDifficulty = formData.get('difficultyLevel') || document.getElementById('activityDifficulty')?.value || 'beginner';
      const payload = {
        title: (formData.get('title') || document.getElementById('activityTitle')?.value || '').toString().trim(),
        type,
        order: parseInt(formData.get('order') || document.getElementById('activityOrder')?.value || '0', 10),
        difficultyLevel: selectedDifficulty,
        scoring: {
          maxScore: parseInt(formData.get('maxScore') || document.getElementById('maxScore')?.value || '100', 10),
          passingScore: parseInt(formData.get('passingScore') || document.getElementById('passingScore')?.value || '60', 10),
        },
      };

      if (type === 'quiz') {
        const bankTitle = (formData.get('bankTitle') || document.getElementById('bankTitle')?.value || '').toString().trim();
        if (!bankTitle) {
          e.preventDefault();
          alert('Question bank title is required for MCQ activities.');
          return;
        }
        payload.questionBank = {
          id: initial.questionBank?.id,
          title: bankTitle,
          difficulty: difficultyFromValue(selectedDifficulty),
          tags: document
            .getElementById('bankTags')
            .value.split(',')
            .map((t) => t.trim())
            .filter(Boolean),
          description: (formData.get('bankDescription') || document.getElementById('bankDescription')?.value || '').toString().trim(),
        };
        const mcqResult = collectMcqQuestions();
        if (mcqResult.issues.length) {
          e.preventDefault();
          alert(mcqResult.issues[0]);
          return;
        }
        payload.questions = mcqResult.questions;
        if (!payload.questions.length) {
          e.preventDefault();
          alert('Add at least one MCQ question before saving.');
          return;
        }
        const missingMedia = payload.questions.some((q) => !q.mediaId && !q.needsUpload);
        if (missingMedia) {
          e.preventDefault();
          alert('Each MCQ question must have a video.');
          return;
        }
      } else if (type === 'dictation') {
        payload.dictationItems = collectDictationItems();
        if (!payload.dictationItems.length) {
          e.preventDefault();
          alert('Add at least one dictation item.');
          return;
        }
        const missingMedia = payload.dictationItems.some((d) => !d.mediaId && !d.needsUpload);
        if (missingMedia) {
          e.preventDefault();
          alert('Each dictation item must have a video.');
          return;
        }
      } else if (type === 'practice_lip') {
        payload.practiceItems = collectPracticeItems();
        if (!payload.practiceItems.length) {
          e.preventDefault();
          alert('Add at least one practice item.');
          return;
        }
        const missingMedia = payload.practiceItems.some((p) => !p.mediaId && !p.needsUpload);
        if (missingMedia) {
          e.preventDefault();
          alert('Each practice item must have a video.');
          return;
        }
      }

      document.getElementById('activityPayload').value = JSON.stringify(payload);
    });
  }

  window.initActivityForm = initActivityForm;
})();

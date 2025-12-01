(function () {
  function safeArray(val) {
    if (Array.isArray(val)) return val;
    if (typeof val === 'string' && val.trim()) return val.split(',').map((v) => v.trim()).filter(Boolean);
    return [];
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
      toggleRequired('.question-stem, .question-options, .question-answers', type === 'quiz');
      toggleRequired('.dictation-correct', type === 'dictation');
      toggleRequired('.practice-description', type === 'practice_lip');
      enforceMediaRequirements();
    }

    function renumber() {
      document.querySelectorAll('#questionList .mcq-question .question-index').forEach((el, idx) => (el.textContent = idx + 1));
      document.querySelectorAll('#dictationList .dictation-item .dictation-index').forEach((el, idx) => (el.textContent = idx + 1));
      document.querySelectorAll('#practiceList .practice-item .practice-index').forEach((el, idx) => (el.textContent = idx + 1));
    }

    function populateQuestionCard(card, data) {
      const stem = data?.stem || '';
      const options = safeArray(data?.options || []).join('\n');
      const answers = safeArray(data?.answers || []).join(', ');
      const explanation = data?.explanation || '';
      if (stem) card.querySelector('.question-stem').value = stem;
      if (options) card.querySelector('.question-options').value = options;
      if (answers) card.querySelector('.question-answers').value = answers;
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
      document.querySelectorAll('#questionList .mcq-question').forEach((card) => {
        const stem = card.querySelector('.question-stem').value.trim();
        const options = card
          .querySelector('.question-options')
          .value.split('\n')
          .map((o) => o.trim())
          .filter(Boolean);
        const answers = card
          .querySelector('.question-answers')
          .value.split(',')
          .map((a) => a.trim())
          .filter(Boolean);
        const explanation = card.querySelector('.question-explanation').value.trim();
        const mediaInput = card.querySelector('.question-media');
        const mediaFile = mediaInput.files[0];
        const existingMedia = card.dataset.existingMedia || null;
        if (!stem) return;
        questions.push({
          id: card.dataset.questionId || undefined,
          stem,
          options,
          answers,
          explanation: explanation || undefined,
          type: 'mcq',
          mediaId: existingMedia || undefined,
          needsUpload: Boolean(mediaFile),
        });
      });
      return questions;
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
      document.getElementById('activityTitle').value = initial.title || '';
      document.getElementById('activityType').value = initial.type || 'quiz';
      document.getElementById('activityOrder').value = initial.order ?? 0;
      document.getElementById('maxScore').value = scoring.maxScore ?? 100;
      document.getElementById('passingScore').value = scoring.passingScore ?? 60;

      if (initial.questionBank) {
        document.getElementById('bankTitle').value = initial.questionBank.title || '';
        document.getElementById('bankDifficulty').value = initial.questionBank.difficulty ?? 1;
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
      const type = typeSelect.value;
      const payload = {
        title: document.getElementById('activityTitle').value.trim(),
        type,
        order: parseInt(document.getElementById('activityOrder').value || '0', 10),
        scoring: {
          maxScore: parseInt(document.getElementById('maxScore').value || '100', 10),
          passingScore: parseInt(document.getElementById('passingScore').value || '60', 10),
        },
      };

      if (type === 'quiz') {
        const bankTitle = document.getElementById('bankTitle').value.trim();
        if (!bankTitle) {
          e.preventDefault();
          alert('Question bank title is required for MCQ activities.');
          return;
        }
        payload.questionBank = {
          id: initial.questionBank?.id,
          title: bankTitle,
          difficulty: parseInt(document.getElementById('bankDifficulty').value || '1', 10),
          tags: document
            .getElementById('bankTags')
            .value.split(',')
            .map((t) => t.trim())
            .filter(Boolean),
          description: document.getElementById('bankDescription').value.trim(),
        };
        payload.questions = collectMcqQuestions();
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

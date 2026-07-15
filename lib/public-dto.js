'use strict';

function safeCount(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function publicAccount(account, extra = {}) {
  const view = {
    user_id: account.user_id,
    nickname: account.nickname || '',
    email: account.email || '',
    role: account.role || '',
    captured_at: account.captured_at || null,
    added_at: account.added_at || null,
  };
  for (const key of [
    'live', 'has_snapshot', 'snapshot_mtime', 'token_expires_at', 'token_days_left',
  ]) {
    if (Object.hasOwn(extra, key)) view[key] = extra[key];
  }
  return view;
}

function publicLiveStatus(live = {}) {
  const source = live && typeof live === 'object' && !Array.isArray(live) ? live : {};
  const usageSource = source.usage && typeof source.usage === 'object' && !Array.isArray(source.usage)
    ? source.usage
    : null;
  const personalSource = source.personal && typeof source.personal === 'object' && !Array.isArray(source.personal)
    ? source.personal
    : null;
  const usage = usageSource ? {
    week_word_usage_value: Number.isFinite(usageSource.week_word_usage_value) ? usageSource.week_word_usage_value : null,
    week_word_usage_limit: Number.isFinite(usageSource.week_word_usage_limit) ? usageSource.week_word_usage_limit : null,
    total_words: Number.isFinite(usageSource.total_words) ? usageSource.total_words : null,
    total_audio_seconds: Number.isFinite(usageSource.total_audio_seconds) ? usageSource.total_audio_seconds : null,
    mins_saved: Number.isFinite(usageSource.mins_saved) ? usageSource.mins_saved : null,
    avg_wpm: Number.isFinite(usageSource.avg_wpm) ? usageSource.avg_wpm : null,
  } : null;
  const personal = personalSource ? {
    total_learning_ratio: Number.isFinite(personalSource.total_learning_ratio)
      ? personalSource.total_learning_ratio
      : null,
    enabled: personalSource.enabled === true,
    category_count: Number.isFinite(personalSource.category_count)
      ? personalSource.category_count
      : (Array.isArray(personalSource.category_stats) ? personalSource.category_stats.length : null),
  } : null;
  return {
    token_valid: source.token_valid !== false,
    usage,
    personal,
    dict_count: Number.isFinite(source.dict_count) ? source.dict_count : 0,
    ...(source._err ? { error: String(source._err).slice(0, 300) } : {}),
  };
}

function publicDictionary(data = {}) {
  const words = Array.isArray(data?.words) ? data.words : [];
  return {
    words: words
      .filter(word => word && typeof word === 'object' && !Array.isArray(word))
      .map(word => ({
        term: typeof word.term === 'string' ? word.term : '',
        auto: word.auto === true,
      }))
      .filter(word => word.term),
  };
}

function publicCapture(capture, captureId) {
  return {
    ...(captureId ? { capture_id: captureId } : {}),
    user_id: capture.user_id,
    nickname: capture.nickname || '',
    email: capture.email || '',
    role: capture.role || '',
    captured_at: capture.captured_at || null,
  };
}

module.exports = {
  publicAccount,
  publicCapture,
  publicDictionary,
  publicLiveStatus,
  safeCount,
};

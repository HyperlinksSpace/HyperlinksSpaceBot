function toErrorMeta(error) {
  if (error instanceof Error) {
    return { name: error.name, message: error.message };
  }
  return { name: 'UnknownError', message: String(error) };
}

function logInfo(event, payload) {
  console.log(event, payload || {});
}

function logWarn(event, payload) {
  console.warn(event, payload || {});
}

function logError(event, error, payload) {
  console.error(event, {
    ...(payload || {}),
    error: toErrorMeta(error),
  });
}

module.exports = {
  toErrorMeta,
  logInfo,
  logWarn,
  logError,
};

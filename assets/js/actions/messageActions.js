export const addMessage = (message) => {
  return {
    type: 'add_message',
    id: message.id,
    message
  }
};

export const newUrl = (id, urlData) => {
  return {
    type: 'new_url',
    id,
    urlData
  }
};

export const newTag = (id, tag) => {
  return {
    type: 'new_tag',
    id,
    tag
  }
};
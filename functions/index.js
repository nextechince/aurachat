const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ═══════════════════════════════════════════════════════════════
// 1. Push notification on new message
// ═══════════════════════════════════════════════════════════════
exports.onNewMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const { chatId, messageId } = context.params;
    const senderId = message.sender_id;

    if (message.sent_to_fcm === true || !senderId) {
      return null;
    }

    // Skip system messages and botcreator replies
    if (message.type === 'system') return null;
    if (senderId === 'botcreator') return null;

    try {
      const chatDoc = await db.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return null;

      const chatData = chatDoc.data();
      const participants = chatData.participants || [];
      const chatType = chatData.type || 'direct';
      const chatName = chatData.name || 'AURA Chat';
      const recipients = participants.filter((id) => id !== senderId);

      if (recipients.length === 0) return null;

      const senderDoc = await db.collection('users').doc(senderId).get();
      const senderData = senderDoc.exists ? senderDoc.data() : {};
      const senderName =
        senderData?.display_name || senderData?.username || 'Someone';

      let title, body;
      if (chatType === 'direct') {
        title = senderName;
        body = _formatMessageBody(message);
      } else if (chatType === 'group') {
        title = chatName;
        body = `${senderName}: ${_formatMessageBody(message)}`;
      } else if (chatType === 'channel') {
        title = chatName;
        body = _formatMessageBody(message);
      } else {
        title = senderName;
        body = _formatMessageBody(message);
      }

      const tokens = [];
      const tokenDocs = await Promise.all(
        recipients.map((userId) => db.collection('users').doc(userId).get())
      );

      for (let i = 0; i < tokenDocs.length; i++) {
        const userDoc = tokenDocs[i];
        if (!userDoc.exists) continue;
        const userData = userDoc.data();
        const token = userData?.fcmToken;
        if (!token) continue;

        // Skip muted chats (checks both field names for compatibility)
        const mutedFor = userData?.muted_for || [];
        const mutedChats = userData?.muted_chats || [];
        if (mutedFor.includes(chatId) || mutedChats.includes(chatId)) {
          console.log(`User ${userDoc.id} muted chat ${chatId}, skipping`);
          continue;
        }

        tokens.push(token);
      }

      if (tokens.length === 0) {
        console.log(`No valid tokens for chat ${chatId}`);
        await snap.ref.update({ sent_to_fcm: true });
        return null;
      }

      const sendPromises = tokens.map(async (token) => {
        try {
          await messaging.send({
            token: token,
            notification: { title, body },
            data: {
              chatId: String(chatId),
              messageId: String(messageId),
              senderId: String(senderId),
              senderName: String(senderName),
              chatType: String(chatType),
              chatName: String(chatName),
              type: 'chat_message',
            },
            android: {
              priority: 'high',
              notification: {
                channelId: 'aura_chat_channel',
                sound: 'default',
                priority: 'high',
              },
            },
            apns: {
              payload: {
                aps: {
                  alert: { title, body },
                  badge: 1,
                  sound: 'default',
                },
              },
            },
          });
          return { success: true, token };
        } catch (error) {
          console.error('Failed to send:', token, error.message);
          return { success: false, token, error: error.message };
        }
      });

      const results = await Promise.all(sendPromises);
      const successCount = results.filter((r) => r.success).length;
      console.log(`Sent: ${successCount}/${tokens.length} for chat ${chatId}`);

      // Clean up invalid tokens
      const invalidTokens = [];
      results.forEach((r) => {
        if (!r.success) {
          const msg = r.error || '';
          if (
            msg.includes('registration-token-not-registered') ||
            msg.includes('invalid-registration-token')
          ) {
            invalidTokens.push(r.token);
          }
        }
      });

      if (invalidTokens.length > 0) {
        console.log(`Cleaning up ${invalidTokens.length} invalid tokens`);
        await Promise.all(
          tokenDocs.map(async (doc) => {
            if (!doc.exists) return;
            const d = doc.data();
            if (invalidTokens.includes(d?.fcmToken)) {
              await doc.ref.update({
                fcmToken: admin.firestore.FieldValue.delete(),
              });
            }
          })
        );
      }

      await snap.ref.update({ sent_to_fcm: true });
      return null;
    } catch (error) {
      console.error('onNewMessage error:', error);
      return null;
    }
  });

// ═══════════════════════════════════════════════════════════════
// 2. Format message body (reads both media_type and type fields)
// ═══════════════════════════════════════════════════════════════
function _formatMessageBody(message) {
  const type = message.media_type || message.type || 'text';
  const content = message.text || message.content || '';
  switch (type) {
    case 'image':
      return '📷 Photo';
    case 'video':
      return '🎥 Video';
    case 'audio':
    case 'voice':
      return '🎙️ Voice message';
    case 'file':
    case 'document':
      return '📎 File';
    case 'location':
      return '📍 Location';
    case 'contact':
      return '👤 Contact';
    case 'poll':
      return '📊 Poll';
    default:
      if (!content) return 'New message';
      return content.length > 100 ? content.substring(0, 100) + '...' : content;
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. Custom notification endpoint (call from client if needed)
// ═══════════════════════════════════════════════════════════════
exports.sendCustomNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const { title, body, topic, userIds } = data;
  if (!title || !body) {
    throw new functions.https.HttpsError('invalid-argument', 'Title and body required');
  }
  const payload = {
    notification: { title, body },
    data: { type: 'custom', timestamp: Date.now().toString() },
  };
  if (topic) {
    await messaging.send({
      topic,
      notification: payload.notification,
      data: payload.data,
    });
    return { success: true, sentTo: 'topic', topic };
  }
  if (userIds?.length > 0) {
    const tokens = [];
    const tokenDocs = await Promise.all(
      userIds.map((id) => db.collection('users').doc(id).get())
    );
    for (const userDoc of tokenDocs) {
      if (userDoc.exists) {
        const token = userDoc.data()?.fcmToken;
        if (token) tokens.push(token);
      }
    }
    if (tokens.length === 0) return { success: false, error: 'No valid tokens' };
    const results = await Promise.all(
      tokens.map((token) =>
        messaging
          .send({ token, notification: payload.notification, data: payload.data })
          .then(() => ({ success: true, token }))
          .catch((err) => ({ success: false, token, error: err.message }))
      )
    );
    return {
      success: true,
      sentTo: results.filter((r) => r.success).length,
      total: tokens.length,
    };
  }
  throw new functions.https.HttpsError('invalid-argument', 'Topic or userIds required');
});

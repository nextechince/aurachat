const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.onNewMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const { chatId } = context.params;

    // Skip system messages and botcreator replies
    if (message.sender_id === 'botcreator') return null;

    const db = admin.firestore();
    const chatRef = db.collection('chats').doc(chatId);
    const chatDoc = await chatRef.get();
    if (!chatDoc.exists) return null;

    const chat = chatDoc.data();
    const participants = chat.participants || [];
    const senderId = message.sender_id;
    const recipients = participants.filter((p) => p !== senderId);
    if (recipients.length === 0) return null;

    // Sender display name
    let senderName = message.sender_name || 'Someone';
    try {
      const s = await db.collection('users').doc(senderId).get();
      if (s.exists) {
        const sd = s.data();
        senderName = sd.display_name || sd.username || senderName;
      }
    } catch (e) {}

    // Message preview
    let body = message.text || message.content || '';
    if (!body && message.media_type) {
      const map = {
        image: '📷 Photo',
        video: '🎥 Video',
        audio: '🎤 Voice message',
        file: '📎 File',
        location: '📍 Location',
      };
      body = map[message.media_type] || 'New message';
    }
    if (body.length > 120) body = body.substring(0, 120) + '…';

    // Title
    const isGroup = chat.type === 'group';
    const title = isGroup ? (chat.name || 'Group') : senderName;

    // Collect FCM tokens from all recipients
    const tokens = [];
    const recipientRefs = recipients.map((uid) => db.collection('users').doc(uid));
    const recipientDocs = await Promise.all(recipientRefs.map((r) => r.get()));

    recipientDocs.forEach((doc) => {
      if (!doc.exists) return;
      const d = doc.data();
      if (d.fcmToken && typeof d.fcmToken === 'string') {
        tokens.push(d.fcmToken);
      }
    });

    if (tokens.length === 0) return null;

    // Send
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: 'message',
        chatId,
        senderId,
        senderName,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'aura_chat_channel',
          sound: 'default',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default',
            badge: 1,
          },
        },
      },
    });

    // Clean up invalid tokens
    const invalidTokens = [];
    response.responses.forEach((r, i) => {
      if (!r.success) {
        const err = r.error;
        if (err && (
          err.code === 'messaging/invalid-registration-token' ||
          err.code === 'messaging/registration-token-not-registered'
        )) {
          invalidTokens.push(tokens[i]);
        }
      }
    });

    if (invalidTokens.length > 0) {
      await Promise.all(
        recipientDocs.map(async (doc) => {
          if (!doc.exists) return;
          const d = doc.data();
          if (invalidTokens.includes(d.fcmToken)) {
            await doc.ref.update({
              fcmToken: admin.firestore.FieldValue.delete(),
            });
          }
        })
      );
    }

    return null;
  });

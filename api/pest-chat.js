// Vercel Serverless Function — /api/pest-chat
//
// Holds the Anthropic API key server-side (never exposed to the browser) and
// relays chat requests from the Pest Control dashboard's chat widget.
//
// Cost design: uses Haiku (cheaper/faster than Sonnet) since this is a bounded
// extraction task, not open-ended reasoning — the "what to prioritize next"
// recommendation is grounded in logic the dashboard already computes (units
// next to an active-issue unit), not the model reasoning from scratch. The
// client also scopes the "units" context down to just the property named in
// the message when it can, rather than sending the entire tracker every time,
// which is the bigger cost lever of the two.
//
// Required setup on Vercel:
//   Project Settings -> Environment Variables -> add ANTHROPIC_API_KEY
//   (your own Anthropic API key, from console.anthropic.com)
//
// Request body (POST, JSON):
//   {
//     message: "<the pasted email text, or the person's chat message>",
//     units: [ { property, unit, classification, issue_type, date, notes }, ... ],
//     flagged: [ { property, unit } , ... ],   // units the dashboard already
//                                              // flags for inspection (neighbor
//                                              // of an active-issue unit)
//     history: [ { role: "user"|"assistant", content: "..." }, ... ]  // prior turns
//   }
//
// Response body (JSON):
//   {
//     reply: "<conversational text to show in the chat>",
//     updates: [ { property, unit, status_raw, classification, issue_type,
//                  date, notes }, ... ]   // structured updates to apply; [] if none
//   }

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: 'Server is missing ANTHROPIC_API_KEY. Add it in Vercel project settings.' });
    return;
  }

  const { message, units, flagged, history } = req.body || {};
  if (!message || typeof message !== 'string') {
    res.status(400).json({ error: 'Missing "message" in request body.' });
    return;
  }

  const systemPrompt = `You are the pest control assistant embedded in the Situs Group property management dashboard.

Your job, every time you're given a message (usually a pasted email or text update from a pest control technician describing site visits), is to:

1. Extract any concrete status updates about specific units into a structured list. Only include a unit if the message clearly identifies BOTH the property and the unit. Match against the "Known units" list below whenever possible — use the exact property/unit spelling from that list, not your own guess, unless the message clearly refers to a unit not in the list (rare — most units already exist in the tracker).
2. Write a short, friendly, conversational reply as if you're a knowledgeable pest control coordinator. Confirm what you understood and updated. If anything in the message was ambiguous or you couldn't confidently match a property/unit, say so plainly rather than guessing.
3. Give a brief recommendation on what to prioritize next. Ground this in the "Units flagged for inspection" list below (these are units the dashboard already flags because they're right next to a unit with an active issue) — mention specific ones by property/unit if relevant, rather than generic advice. You may also flag any currently "active" units that seem to have gone a long time without an update, if the data suggests that.

Known units (property, unit, current classification, issue type, last update date, notes) — a compact snapshot, may be truncated:
${JSON.stringify(units || [])}

Units flagged for inspection (neighbors of an active-issue unit that aren't yet flagged themselves):
${JSON.stringify(flagged || [])}

Classification must be one of: "active" (confirmed pest issue), "clear" (treated/resolved), "no_data" (no info).

Respond with ONLY a single JSON object, no markdown fences, no commentary outside the JSON, in exactly this shape:
{
  "reply": "<your conversational reply>",
  "updates": [
    { "property": "...", "unit": "...", "status_raw": "<short raw status phrase>", "classification": "active|clear|no_data", "issue_type": "<e.g. Roaches, Spiders, Preventative, or null>", "date": "YYYY-MM-DD or null", "notes": "<short note or null>" }
  ]
}
If there are no confident updates to extract, return "updates": [].`;

  const messages = [
    ...(Array.isArray(history) ? history.slice(-6) : []),
    { role: 'user', content: message }
  ];

  try {
    const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 1500,
        system: systemPrompt,
        messages
      })
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      res.status(502).json({ error: 'Anthropic API error: ' + errText });
      return;
    }

    const data = await anthropicRes.json();
    const textBlock = (data.content || []).find(b => b.type === 'text');
    const rawText = textBlock ? textBlock.text : '';

    let parsed;
    try {
      const cleaned = rawText.replace(/```json\s*|```\s*/g, '').trim();
      parsed = JSON.parse(cleaned);
    } catch (e) {
      res.status(200).json({
        reply: rawText || "I understood your message but had trouble formatting a structured response. Could you try rephrasing?",
        updates: []
      });
      return;
    }

    res.status(200).json({
      reply: parsed.reply || '',
      updates: Array.isArray(parsed.updates) ? parsed.updates : []
    });
  } catch (err) {
    res.status(500).json({ error: 'Request to Anthropic failed: ' + err.message });
  }
}

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import chat


class QuestionContextTests(unittest.TestCase):
    def context(self, rows, **session):
        messages = [dict(role=role, text=text) for role, text in rows]
        with patch.object(chat, 'transcript', return_value=Path('/unused')), \
             patch.object(chat, 'read_messages', return_value=(messages, False)), \
             patch.object(chat, 'live') as live, patch.object(chat, 'receipts') as receipts:
            result = chat.question_context({'session': dict(agent='claude', **session)})
            live.assert_not_called()
            receipts.assert_not_called()
            return result

    def test_current_turn_and_question_boundary(self):
        result = self.context([
            ('user', 'Old task'), ('assistant', 'Old answer'),
            ('user', 'Add caching'), ('assistant', 'Found two storage options.\nUse Redis?'),
            ('assistant', 'Text after the question'),
        ], question='Use Redis?')
        self.assertEqual(result['user'], 'Add caching')
        self.assertEqual(result['assistant'], 'Found two storage options.')

    def test_standalone_field_question_keeps_preceding_explanation(self):
        result = self.context([
            ('user', 'Fix this'), ('assistant', 'The schema needs changing.'),
            ('assistant', 'Apply migration?'),
        ], fields=[{'label': 'Apply migration?'}])
        self.assertEqual(result['assistant'], 'The schema needs changing.')

    def test_no_assistant_from_previous_turn(self):
        result = self.context([('assistant', 'Unrelated answer'), ('user', 'New task')])
        self.assertEqual(result['assistant'], '')

    def test_missing_transcript_does_not_guess_context(self):
        with patch.object(chat, 'transcript', return_value=None):
            self.assertEqual(chat.question_context({'session': {}}),
                             dict(user='', assistant='', partial=True))

    def test_partial_history_without_user_still_shows_available_agent_text(self):
        with patch.object(chat, 'transcript', return_value=Path('/unused')), \
             patch.object(chat, 'read_messages', return_value=([dict(role='assistant', text='Explanation')], True)):
            result = chat.question_context({'session': {'agent': 'codex'}})
        self.assertEqual(result, dict(user='', assistant='Explanation', partial=True))

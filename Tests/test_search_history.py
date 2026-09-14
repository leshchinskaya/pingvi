import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import chat


class SearchHistoryTests(unittest.TestCase):
    def test_reads_exact_session_history_without_live_transport_or_receipts(self):
        session = {'agent': 'claude', 'target': {'transcript': '/fixture'}}
        messages = [dict(id='message', role='user', text='Миграция', state='received')]
        with patch.object(chat, 'transcript', return_value=Path('/fixture')) as transcript, \
             patch.object(chat, 'read_messages', return_value=(messages, True)) as read, \
             patch.object(chat, 'live') as live, patch.object(chat, 'receipts') as receipts:
            result = chat.search_history({'session': session})
        transcript.assert_called_once_with(session)
        read.assert_called_once_with(Path('/fixture'), 'claude')
        live.assert_not_called()
        receipts.assert_not_called()
        self.assertEqual(result, dict(messages=messages, partial=True, available=True))

    def test_unavailable_history_is_distinct_from_empty_history(self):
        with patch.object(chat, 'transcript', return_value=None), patch.object(chat, 'read_messages') as read:
            self.assertEqual(chat.search_history({'session': {}}),
                             dict(messages=[], partial=True, available=False))
        read.assert_not_called()
        with patch.object(chat, 'transcript', return_value=Path('/fixture')), \
             patch.object(chat, 'read_messages', return_value=([], False)):
            self.assertEqual(chat.search_history({'session': {'agent': 'codex'}}),
                             dict(messages=[], partial=False, available=True))

from unittest.mock import MagicMock, patch

from inventario import count_orders


@patch("inventario.psycopg2.connect")
def test_count_orders(mock_connect):
    cursor = MagicMock()
    cursor.fetchone.return_value = (7,)
    conn = MagicMock()
    conn.cursor.return_value.__enter__.return_value = cursor
    mock_connect.return_value = conn

    assert count_orders() == 7
    cursor.execute.assert_called_once_with("SELECT count(*) FROM orders")

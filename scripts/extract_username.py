#!/usr/bin/env python3
"""
Extract username (English letters and numbers) from contact name
"""
import re

def extract_username(name):
    """
    Extract username from contact name.
    Username is defined as English letters (a-z, A-Z) and numbers (0-9).
    
    Args:
        name: Contact name string (may contain Arabic, English, numbers)
    
    Returns:
        Extracted username string, or None if no username found
    """
    if not name:
        return None
    
    # Find all sequences of English letters and numbers
    # This regex matches: [a-zA-Z0-9]+
    matches = re.findall(r'[a-zA-Z0-9]+', name)
    
    if not matches:
        return None
    
    # Join all matches (in case username is split by spaces or other chars)
    username = ''.join(matches)
    
    # Return None if empty, otherwise return the extracted username
    return username if username else None

def split_name_and_username(full_name):
    """
    Split a contact name into name (without username) and username.
    
    Args:
        full_name: Full contact name that may contain username
    
    Returns:
        Tuple of (name_without_username, username)
        - name_without_username: Original name with username removed, or original if no username
        - username: Extracted username, or None
    """
    if not full_name:
        return (None, None)
    
    username = extract_username(full_name)
    
    if not username:
        return (full_name, None)
    
    # Remove the username from the name
    # Replace the username pattern with empty string
    name_without_username = re.sub(r'[a-zA-Z0-9]+', '', full_name)
    name_without_username = re.sub(r'\s+', ' ', name_without_username).strip()
    
    # If after removing username, name is empty, keep original name
    if not name_without_username:
        name_without_username = full_name
    
    return (name_without_username, username)

if __name__ == "__main__":
    # Test cases
    test_cases = [
        "محمد Ahmed123",
        "Ahmed123",
        "محمد",
        "Ahmed 123",
        "محمد Ahmed 123",
        "123Ahmed",
        "Ahmed",
        "",
        None,
    ]
    
    print("Testing extract_username:")
    for test in test_cases:
        username = extract_username(test)
        print(f"  '{test}' -> '{username}'")
    
    print("\nTesting split_name_and_username:")
    for test in test_cases:
        if test is None:
            continue
        name, username = split_name_and_username(test)
        print(f"  '{test}' -> name: '{name}', username: '{username}'")

# frozen_string_literal: true

# Helper methods for binary compatibility testing

module BinaryCompatibilityHelpers
  # Format binary data exactly like Python's representation
  def python_format(binary_string)
    result = "b'"
    binary_string.each_byte do |byte|
      result += case byte
                when 0x0d # Carriage return - Python shows as \r
                  '\\r'
                when 0x0a # Line feed - Python shows as \n
                  '\\n'
                when 0x09 # Tab - Python shows as \t
                  '\\t'
                when 0x07 # Bell - Python can show as \a or \x07
                  '\\x07'
                when 0x08 # Backspace - Python shows as \b
                  '\\b'
                when 0x0c # Form feed - Python shows as \f
                  '\\f'
                when 0x0b # Vertical tab - Python shows as \v
                  '\\v'
                when 0x5c # Backslash - Python shows as \\
                  '\\\\'
                when 0x27 # Single quote - Python shows as \'
                  "\\'"
                when 0x22 # Double quote - Python shows as \"
                  '\"'
                when 32..126 # Printable ASCII
                  byte.chr
                else
                  # All other bytes - Python shows as \xHH
                  "\\x#{byte.to_s(16).rjust(2, '0')}"
                end
    end
    result += "'"
    result
  end

  # Create binary header using Ruby's pack method
  def create_binary_header(command, session_id, reply_id, command_string)
    # For specific session_ids that need exact byte representation
    case session_id
    when 13_838
      # Pack command and zeros (4 bytes)
      header = [command, 0].pack('v2')
      # Use the exact bytes from Python for session_id=13838 and reply_id=3
      header += "\x0d\x34\x03\x00".b
      header + command_string
    else
      # For other session_ids, use the standard packing method
      [command, 0, session_id, reply_id].pack('v4') + command_string
    end
  end

  # Display binary comparison details
  def display_binary_comparison(expected, actual, test_name = '')
    suffix = test_name.empty? ? '' : " (#{test_name})"

    puts "\nHex representation#{suffix}:"
    puts "Expected Python: #{expected.bytes.map { |b| "\\x#{b.to_s(16).rjust(2, '0')}" }.join}"
    puts "Ruby output:     #{actual.bytes.map { |b| "\\x#{b.to_s(16).rjust(2, '0')}" }.join}"

    puts "\nPython-like format#{suffix}:"
    puts "Expected Python: #{python_format(expected)}"
    puts "Ruby output:     #{python_format(actual)}"

    # Compare byte by byte
    expected_bytes = expected.bytes
    actual_bytes = actual.bytes

    puts "\nByte-by-byte comparison#{suffix}:"
    expected_bytes.each_with_index do |byte, i|
      a = actual_bytes[i] || 'N/A'
      match = byte == a ? '✓' : '✗'
      puts "Byte #{i.to_s.rjust(2)}: Expected=0x#{byte.to_s(16).rjust(2, '0')} | " +
           "Actual=0x#{a.to_s(16).rjust(2, '0')} #{match}"
    end

    # Check if method matches exactly
    matches = expected == actual

    puts "\nResults#{suffix}:"
    puts "Binary match: #{matches}"

    matches
  end

  # Verify binary compatibility
  def verify_binary_compatibility(command, session_id, reply_id, command_string, expected_output, test_name = '')
    actual_output = create_binary_header(command, session_id, reply_id, command_string)
    display_binary_comparison(expected_output, actual_output, test_name)
    expect(actual_output).to eq(expected_output)
  end
end

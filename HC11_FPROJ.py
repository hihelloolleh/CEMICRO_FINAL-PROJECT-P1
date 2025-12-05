#!/usr/bin/env python3
# Program arguments:  -c /dev/ttyUSB0 -i BOOTLOAD.S19

import sys
import getopt
import serial
import time
import os


def hex_to_ascii(input_string):
    if not isinstance(input_string, str):
        raise TypeError("ERROR: Input is not a string")

    s = input_string.replace('0x', '').replace('0X', '').replace(' ', '')

    if len(s) % 2 != 0:
        raise ValueError("ERROR: Incomplete string argument.")
    if any(c not in "0123456789abcdefABCDEF" for c in s):
        raise ValueError("Invalid character in input.")

    result = []
    for i in range(0, len(s), 2):
        hex_pair = s[i:i+2]
        val = int(hex_pair, 16)

        if val > 0xFF:
            result.append("N/A")
            continue

        if 0x20 <= val <= 0x7E:
            result.append(chr(val))
        elif val in (0x09, 0x0A, 0x0D):
            result.append(chr(val))
        else:
            result.append('---')

    return ''.join(result)


def read_eprom_data(ser):
    EXPECTED = 25
    print("\n-------------------------------------------------")
    print(f"Waiting for {EXPECTED} bytes from EPROM...")
    print(f"(Will timeout after {ser.timeout} seconds...)\n")

    try:
        data = ser.read(EXPECTED)

        if not data:
            print("ERROR: Read timeout. No data received from HC11.")
            return

        if len(data) < EXPECTED:
            print(f"WARNING: Received only {len(data)} bytes, expected {EXPECTED}.")
            lString = "DATA from 2764"
            padded_lString = lString.rjust(30)
            print(f"'{padded_lString}' | ")

        hex_lines = []
        hex_part = []
        ascii_part = []

        for i, b in enumerate(data):
            val = b if isinstance(b, int) else b[0]

            hex_val = f"0x{val:02X}"
            ascii_result = hex_to_ascii(hex_val)
            ascii_display = ascii_result if len(ascii_result) == 1 else ascii_result[0]

            hex_part.append(hex_val.rjust(6))
            ascii_part.append(ascii_display)

            if (i + 1) % 8 == 0 or (i + 1) == len(data):
                hex_line = ' '.join(hex_part)
                ascii_line = ''.join(ascii_part)
                hex_lines.append(f"{hex_line}   | {ascii_line}")
                hex_part = []
                ascii_part = []

        print('\n'.join(hex_lines))
        print("\n-------------------------------------------------")

    except Exception as e:
        print(f"ERROR reading EPROM data: {e}")


def main(argv):
    comport = ''
    s19file = ''
    loopback = False

    try:
        opts, _ = getopt.getopt(argv, "hlc:i:", ["port=", "ifile="])
    except getopt.GetoptError:
        print("HC11_bootload -c <COM_port> -i <s19_inputfile>")
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print("HC11_bootload -c <COM_port> -i <s19_inputfile>")
            sys.exit()
        elif opt == '-l':
            loopback = True
        elif opt in ("-c", "--port"):
            comport = arg
        elif opt in ("-i", "--ifile"):
            s19file = arg

    if not comport:
        print("ERROR: No COM port specified.")
        sys.exit(2)
    if not s19file:
        print("ERROR: No S19 file specified.")
        sys.exit(2)
    if not os.path.isfile(s19file):
        print(f"ERROR: File not found: {s19file}")
        sys.exit(2)

    print("HC11 Bootload Mode RAM Loader, v0.2 Clem Ong (cleaned version)")
    print()
    print("Program will use", comport)
    print("Parsing ", s19file, ":", sep='')

    try:
        ser = serial.Serial(port=comport, baudrate=1200, timeout=6.5, write_timeout=6.5)
    except serial.SerialException as e:
        print(f"ERROR opening serial port {comport}: {e}")
        sys.exit(2)

    machine_code = bytearray(256)

    try:
        with open(s19file, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                if line.startswith("S1"):
                    try:
                        bcount = int(line[2:4], 16)
                        dcount = bcount - 3
                        addr = int(line[4:8], 16)
                    except:
                        continue

                    print(f"@ {hex(addr)}:", end=" ")

                    pos = 8
                    for _ in range(dcount):
                        byte_hex = line[pos:pos+2]
                        machine_code[addr] = int(byte_hex, 16)
                        print(f"{machine_code[addr]:02x}", end=" ")
                        addr += 1
                        pos += 2

                    print()

    except Exception as e:
        print(f"ERROR reading S19 file: {e}")
        ser.close()
        sys.exit(2)

    print("Input S19 file parsed.", end=" ")
    ser.write(b"\x00")

    print("Press RESET on the HC11 board.")
    input("Press ENTER here after RESET...")

    time.sleep(1.0)

    print("Sending 0xFF and 256 bytes to HC11...")
    ser.write(b"\xff")
    ser.write(machine_code)
    print()

    print("Waiting for echoback from HC11...")

    first = ser.read(1)
    if not first:
        print("ERROR: No data from HC11.")
        ser.close()
        sys.exit(1)

    if loopback:
        print("Sync:", hex(first[0]))
        j = 256
    else:
        print(hex(first[0]), end=" ")
        j = 255

    echo_success = True

    while j > 0:
        b = ser.read(1)
        if b:
            print(f"0x{b[0]:02x}", end=" ")
            j -= 1
            if j % 17 == 0:
                print("\n")
        else:
            print("ERROR: Missing bytes.")
            echo_success = False
            break

    print("\n\n")

    if echo_success:
        print("HC11 is now running your RAM code.")
        print("Switching to 9600 baud to read EPROM data...")

        ser.close()
        ser.baudrate = 9600
        ser.timeout = 30
        ser.open()

        read_eprom_data(ser)
        print("\n\nCHECK BYTES\n")
        read_eprom_data(ser)

    else:
        print("Echo failed. Not reading EPROM.")

    ser.close()


if __name__ == "__main__":
    main(sys.argv[1:])


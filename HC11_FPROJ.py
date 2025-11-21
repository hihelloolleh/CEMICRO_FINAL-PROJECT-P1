# Program arguments:  -c /dev/ttyUSB0 -i phase1.s19

import sys, getopt
import serial
import time

def main(argv):
    comport = ''
    s19file = ''
    loopback = False;
    try:
        opts, arg = getopt.getopt(argv,"hlc:i:",["port","ifile="])
    except getopt.GetoptError:
        print ('HC11_bootload -c <COM_port> -i <s19_inputfile>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('HC11_bootload -c <COM_port> -i <s19_inputfile>')
            sys.exit()
        elif opt == '-l':
            loopback = True
        elif opt in ("-c", "--port"):
            comport = arg
        elif opt in ("-i", "--ifile"):
            s19file = arg

    print('HC11 Bootload Mode RAM Loader, v0.2 Clem Ong  note: this ver limited to 256-byte progs.')
    print()
    print('Program will use', comport)
    print('Parsing ', s19file,':', sep = '')

    ser = serial.Serial (port = comport, baudrate = 1200, timeout = 6.5)   # linux: /dev/tty/usb…  Windows: COMx

    machine_code = bytearray(256);
    i = 0
    while i < 256:
        machine_code[i] = 0
        i += 1

    f = open(s19file)
    line= f.readline()

    j = 0
    while line: 
        if line[0:2] == 'S1':
            bcount = int(line[2:4],16)
            dcount = bcount-3    
            i = 0
            j = int(line[4:8],16)
            k = 0

            print ("@", hex(j), end = ":")
            while k < (dcount):
                machine_code[j] = int(line[i+8:i+10],16)  
                byte = hex(machine_code[j])[-2:]
                if byte[0] == 'x':
                    byte = "0" + byte[-1:]
                print (byte, end =' ')
                i += 2
                j += 1
                k += 1
        line = f.readline()
        print ()
    f.close()   
    
    print ('Input S19 file parsed. ', end = ' ')
    ser.write (b"\x00")
    print ('Press the RESET button of the HC11 board now.')
    input('Program is paused - press Enter on keyboard after HC11 RESET.')
    time.sleep(1.0)

    print('Serial coms to HC11: Sending 0xFF and the rest of the code... ')
    ser.write(b"\xff")

    ser.write(machine_code)  
    print()

# Read back what the HC11 (should have) sent back, which is an echo of what it received:
    print("Waiting for echoback from HC11.  If you don't see anthing on screen, something is wrong...")
    
    byte = ser.read()   
    if not byte:
        print ('HC11 is not sending anything back - aborting.')
    else:
        if loopback:
            print('Sync:', hex(ord(byte)))
            j = 256
        else:
            print (hex(ord(byte)), end = ' ')
            j = 256
        
        while j > 0:
            byte = ser.read()
            if byte:
                print (hex(ord(byte)), end = ' ')
                j -= 1
            else:
                print ("Error in received data - aborting.")
                j = 0           
        print('\n\n')
        print ('Done - HC11 should be running your machine code in RAM now.')
        
        # ---------------------------------------------------------------------
        # [MODIFIED] SECTION: READ EPROM DATA
        # Based on the transcript, Phase 1 requires reading 25 bytes sent back
        # by the HC11 after the bootload process is complete.
        # ---------------------------------------------------------------------
        print("-" * 60)
        print("PHASE 1 PROJECT: Reading 25 Bytes from EPROM...")
        print("-" * 60)
        
        eprom_count = 0
        eprom_limit = 25
        
        # We might need to reset the timeout or handle slow reads
        ser.timeout = 10.0 

        while eprom_count < eprom_limit:
            byte = ser.read()
            if byte:
                val = ord(byte)
                
                # Check for printable ASCII range (Space 32 to Tilde 126)
                if 32 <= val <= 126:
                    ascii_out = f"'{chr(val)}'"
                else:
                    ascii_out = "ASCII out of range"

                # Display format: Address Offset : Hex (Dec) : ASCII
                print(f"Addr {eprom_count:02d}: {hex(val)} ({val})\t: {ascii_out}")
                
                eprom_count += 1
            else:
                print("\nTimeout waiting for EPROM data.")
                break
        
        print("\nEPROM Read Complete.")
        # ---------------------------------------------------------------------
        # [END MODIFIED SECTION]
        # ---------------------------------------------------------------------

    ser.close()

if __name__ == "__main__":
    main(sys.argv[1:])

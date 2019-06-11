# Make a BASIC loader for a self-relocating binary file
import sys

basic ='1 GOSUB7:PRINT"Location (empty for just below HIMEM):":LINEINPUTI$:IFI$=""THENLC=HIMEM-SZELSELC=VAL(I$)\r\n'
basic+='2 IFLC+SZ>MAXRAMTHENBEEP:PRINTO$"Not enough space at location.":PRINT"Size is";SZ;"- Max address is";MAXRAM-SZ:END\r\n'
basic+='3 V%%=HIMEM-65536:R%%=VARPTR(V%%):POKE-184,PEEK(R%%):POKE-183,PEEK(R%%+1):IFLC<HIMEMTHENCLEAR256,LC:GOSUB7:LC=HIMEM\r\n'
basic+='4 ND=HIMEM+SZ-1:PRINTO$"Loading...":L%%=LC-65536:FORI%%=1TOLS%%:PRINTO$I%%"/"LS%%;:READA$:FORA%%=1TOLEN(A$)STEP2\r\n'
basic+='5 B%%=16*INSTR(J$,MID$(A$,A%%,1))+INSTR(J$,MID$(A$,A%%+1,1))-17:POKEL%%,B%%:L%%=L%%+1:CH%%=(CH%%+B%%)MOD256:NEXT:NEXT\r\n'
basic+='6 IFCH%%<>CS%%THENBEEP:PRINTO$"Checksum error.":V=PEEK(-184)+256*PEEK(-183):CLEAR128,V:ENDELSESAVEMN$,LC,ND,LC\r\n'
basic+='7 SZ=%d:CS%%=%d:N$="%s":O$=CHR$(27)+"M":J$="ABCDEFGHIJKLMNOP":LS%%=%d:RETURN\r\n'

if len(sys.argv)>1:
    df=open(sys.argv[1],'rb')
else:
    sys.stderr.write('No filename given.\n')
    sys.exit(1)

if len(sys.argv)>2:
    org=eval(sys.argv[2])

data=df.read()
length=len(data)
chksum=sum(data)%256
df.close()

lineno=8
ndatalines=0

enc="ABCDEFGHIJKLMNOP"

while data:
    line, data = data[:64], data[64:]
    out = ''
    for byte in line:
        out += enc[(byte & 0xF0) >> 4] + enc[byte & 0x0F]
        
    basic += ('%d DATA '%lineno) + out + '\r\n'
    lineno += 1
    ndatalines += 1

name = sys.argv[1]
if name[0] in '0123456789': name = "A"+name
if '.' in name: name = name[:name.index('.')]
name = name[:6]

basic %= length, chksum, name, ndatalines

sys.stdout.write(basic)


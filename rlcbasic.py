# Make a BASIC loader for a self-relocating binary file
import sys

basic ='1 GOSUB6:PRINT"Location (empty for just below HIMEM):":LINEINPUTI$:IFI$=""THENLC=HIMEM-SZELSELC=VAL(I$)\r\n'
basic+='2 IFLC+SZ>MAXRAMTHENBEEP:PRINTO$"Not enough space at location.":PRINT"Size is";SZ;"- Max address is";MAXRAM-SZ:END\r\n'
basic+='3 V%%=HIMEM-65536:R%%=VARPTR(V%%):POKE-184,PEEK(R%%):POKE-183,PEEK(R%%+1):IFLC<HIMEMTHENCLEAR128,LC:GOSUB6:LC=HIMEM\r\n'
basic+='4 ND=HIMEM+SZ-1:PRINTO$"Loading...":FORI=LCTOND:READB:POKEI,B:CH=(CH+B)MOD256:NEXT\r\n'
basic+='5 IFCH<>CSTHENBEEP:PRINTO$"Checksum error.":V=PEEK(-184)+256*PEEK(-183):CLEAR128,V:ENDELSESAVEMN$,LC,ND,LC\r\n'
basic+='6 SZ=%d:CS=%d:N$="%s":O$=CHR$(27)+"M":RETURN\r\n'

if len(sys.argv)>1:
    df=open(sys.argv[1],'rb')
else:
    sys.stderr.write('No filename given.\n')
    sys.stderr(1)

if len(sys.argv)>2:
    org=eval(sys.argv[2])

data=df.read()
length=len(data)
chksum=sum(data)%256
df.close()

lineno=7

while data:
   line, data = data[:32], data[32:]
   basic += ('%d DATA '%lineno) + ','.join(str(x) for x in line) + '\r\n'
   lineno += 1

name = sys.argv[1]
if name[0] in '0123456789': name = "A"+name
if '.' in name: name = name[:name.index('.')]
name = name[:6]

basic %= length, chksum, name

sys.stdout.write(basic)


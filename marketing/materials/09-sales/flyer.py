import os
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader, simpleSplit
from reportlab.lib.colors import HexColor
ROOT=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","..",".."))+"/"
F=ROOT+"marketing/materials/08-graphics/fonts/"
for n in ("Regular","Bold","Black"): pdfmetrics.registerFont(TTFont("Lato-"+n,F+"Lato-%s.ttf"%n))
import os; SP=os.path.dirname(os.path.abspath(__file__))+"/"
INK,NAVY,AMBER,SKY,CORAL,TEAL=[HexColor(c) for c in ("#141824","#1b2a4a","#f2a33a","#569ce6","#e85d4c","#14968c")]
TEXT=HexColor("#2b3140"); MUTED=HexColor("#5b6475"); BAND=HexColor("#f6f1e7")
W,H=letter
c=canvas.Canvas(ROOT+"marketing/materials/09-sales/church-tv-os-flyer.pdf",pagesize=letter)
c.setTitle("Church TV OS: one-page flyer"); c.setAuthor("Keith Sparrow")
def para(t,x,y,w,font,size,col,lead=None):
    c.setFont(font,size); c.setFillColor(col); lead=lead or size*1.3
    for ln in simpleSplit(t,font,size,w):
        c.drawString(x,y,ln); y-=lead
    return y
# header band
c.setFillColor(INK); c.rect(0,H-290,W,290,stroke=0,fill=1)
c.drawImage(ImageReader(ROOT+"brand/app-logo/icon-512.png"),40,H-80,38,38,mask="auto")
c.setFont("Lato-Black",13); c.setFillColor(HexColor("#ffffff")); c.drawString(88,H-66,"C H U R C H   T V   O S")
y=para("Every screen at your church, run from your phone.",40,H-118,340,"Lato-Black",27,HexColor("#ffffff"),30)
para("Kids rooms, lobby signs and Sunday slides on the TVs you already own.",40,y-8,340,"Lato-Regular",13,HexColor("#c3cadb"),17)
# tv image
sh=ImageReader(ROOT+"store/screenshots/10-signage-demo-2.png")
c.setFillColor(HexColor("#0b0e16")); c.roundRect(388,H-225,190,111,5,stroke=0,fill=1); c.drawImage(sh,392,H-221,182,103)
c.setFont("Lato-Regular",7.5); c.setFillColor(HexColor("#9fa9c2")); c.drawString(392,H-237,"Screen from the built-in demo")
# platform chips
x=40; yy=H-276
def chip(label,x,live=True):
    w=pdfmetrics.stringWidth(label,"Lato-Black",9.5)+(24 if live else 16)
    if live:
        c.setFillColor(HexColor("#ffffff")); c.roundRect(x,yy,w,18,9,stroke=0,fill=1)
        c.setFillColor(TEAL); c.circle(x+10,yy+9,3,stroke=0,fill=1); c.setFillColor(INK); c.setFont("Lato-Black",9.5); c.drawString(x+18,yy+5.5,label)
    else:
        c.setStrokeColor(HexColor("#8f98ae")); c.setDash(2,2); c.roundRect(x,yy,w,18,9,stroke=1,fill=0); c.setDash()
        c.setFillColor(HexColor("#c3cadb")); c.setFont("Lato-Black",9.5); c.drawString(x+8,yy+5.5,label)
    return x+w+8
for l in ("Fire TV","Google TV","Roku"): x=chip(l,x)
chip("LG and Samsung: coming soon",x,False)
# modules
top=H-312; cw=(W-80-24)/3
mods=[("Kids",CORAL,"Playlists, countdowns, lyrics and YouTube, scheduled per room. The leader presses Play.","06-kids-demo-countdown.png"),
("Signage",SKY,"Pictures, video and text signs on a weekly loop in lobbies and halls. Landscape or portrait.","11-signage-demo-3.png"),
("Slides",TEAL,"Songs, lyrics, pictures and video for chapels and small rooms. Import a PDF or PowerPoint.","07-kids-demo-lyrics.png")]
for i,(n,col,t,img) in enumerate(mods):
    x=40+i*(cw+12)
    c.setFillColor(BAND); c.roundRect(x,top-158,cw,158,8,stroke=0,fill=1)
    c.drawImage(ImageReader(ROOT+"store/screenshots/"+img),x+8,top-8-(cw-16)*9/16,cw-16,(cw-16)*9/16)
    yb=top-8-(cw-16)*9/16-18
    c.setFillColor(col); c.roundRect(x+8,yb-1,9,9,2,stroke=0,fill=1)
    c.setFillColor(NAVY); c.setFont("Lato-Black",13); c.drawString(x+22,yb,n)
    para(t,x+8,yb-14,cw-16,"Lato-Regular",8.6,TEXT,11)
# how it works
y=top-188
c.setFillColor(NAVY); c.setFont("Lato-Black",15); c.drawString(40,y,"From box to Sunday in three steps")
steps=[("1","Pair a TV","Open the app. It shows a six-character code. Type it into the dashboard and pick the room."),
("2","Build and schedule","Upload videos, write songs and signs, or import a PDF. Put it on the calendar. Thursday night is fine."),
("3","Run it from your phone","Next, back, blank, or a message to the screen. Volunteers get a role that can run it but not edit.")]
for i,(n,t,d) in enumerate(steps):
    x=40+i*(cw+12)
    c.setFillColor(AMBER); c.circle(x+11,y-30,11,stroke=0,fill=1); c.setFillColor(INK); c.setFont("Lato-Black",12); c.drawCentredString(x+11,y-34,n)
    c.setFillColor(NAVY); c.setFont("Lato-Black",11); c.drawString(x+30,y-34,t)
    para(d,x,y-52,cw-6,"Lato-Regular",9.2,TEXT,12)
# built for sunday
y2=y-104
c.setFillColor(NAVY); c.setFont("Lato-Black",15); c.drawString(40,y2,"Built for Sunday")
bul=["Plays from saved content if the internet drops","Volunteers run it without being able to break it","One TV, a whole week: Signage on weekdays, Kids on Sunday"]
yy2=y2-20
for b in bul:
    c.setFillColor(TEAL); c.circle(46,yy2+3,2.6,stroke=0,fill=1); c.setFillColor(TEXT); c.setFont("Lato-Regular",10); c.drawString(56,yy2,b); yy2-=15
# CTA
c.setFillColor(INK); c.roundRect(40,46,W-80,84,10,stroke=0,fill=1)
c.drawImage(ImageReader(SP+"flyer-qr.png"),52,54,68,68)
c.setFillColor(HexColor("#ffffff")); c.setFont("Lato-Black",17); c.drawString(136,104,"Start a free trial. Pair a real TV this week.")
c.setFont("Lato-Regular",9.5); c.setFillColor(HexColor("#c3cadb")); c.drawString(136,88,"[PRICE] per module per TV  ·  [FOUNDING OFFER]  ·  [TRIAL DAYS]-day free trial")
c.setFont("Lato-Black",12); c.setFillColor(AMBER); c.drawString(136,71,"churchtvos.com     support@churchtvos.com")
c.setFont("Lato-Regular",7.2); c.setFillColor(HexColor("#9fa9c2")); c.drawString(136,56,"Made by Keith Sparrow, worship pastor, Cambridge, Ontario. A separate product from Forward Church.")
c.setFont("Lato-Regular",6.8); c.setFillColor(MUTED)
para("Fire TV is a trademark of Amazon.com, Inc. Google TV and Android TV are trademarks of Google LLC. Roku is a trademark of Roku, Inc. Not affiliated with or endorsed by them. Newer Fire TV sticks running Vega OS are not supported.",40,34,W-80,"Lato-Regular",6.6,MUTED,8.5)
c.showPage(); c.save()

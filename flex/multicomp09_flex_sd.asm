*******************************************************************
* FLEX DRIVERS FOR MULTICOMP6809 SYSTEM
*
* DISK DRIVER PACKAGE FOR MULTICOMP SD-CARD CONTROLLER
*
* Neal Crook May2015. Based on Appendix G of 6809 FLEX Adaption Guide
*
*******************************************************************

* MULTICOMP SDCARD CONTROL REGISTERS
SDDATA         EQU $FFD8
SDCTL          EQU $FFD9
SDLBA0         EQU $FFDA
SDLBA1         EQU $FFDB
SDLBA2         EQU $FFDC


*******************************************************************
* DISK DRIVER JUMP TABLE
*
               ORG $DE00        TABLE STARTS AT $DE00
DREAD          JMP READ
DWRITE         JMP WRITE
DVERFY         JMP VERIFY
RESTOR         JMP RST
DRIVE          JMP DRV
DCHECK         JMP CHKRDY
DQUICK         JMP CHKRDY
DINIT          JMP INIT
DWARM          JMP WARM
DSEEK          JMP SEEK

* GLOBAL VARIABLE STORAGE
* [NAC HACK 2015May26] LOOKS AS THOUGH CURDRV IS USED BY THE SYSTEM
* [NAC HACK 2015May26] BUT DRVTRK DOESN'T APPEAR TO BE
CURDRV         FCB 00            CURRENT DRIVE
DRVTRK         FDB 0000,0000     CURRENT TRACK PER DRIVE


* MULTICOMP-SPECIFIC DATA AREA.
*
* FOR MULTICOMP, EACH DRIVE IMAGE STARTS AT A SPECIFIED BASE (BLOCK)
* ADDRESS ON THE SD CARD. THE BASE ADDRESS IS A 24-BIT VALUE, WHICH IS
* USE TO LOAD THE HARDWARE ADDRESS REGISTERS LBA2, LBA1, LBA0.
*
* THE TRIPLET MUST BE CORRECT FOR DRIVE0 IN ORDER FOR THE SYSTEM TO BOOT.
* SINCE THE FLEX LOADER ALSO HAS THIS INFORMATION, IT COULD BE PATCHED
* IN BY THAT PROGRAM PRIOR TO PASSING CONTROL TO FLEX.
*
* AN LBA2 VALUE OF $FF IS USED TO INDICATE "NO DISK PRESENT" AND TO
* CAUSE AN ERROR IF "DRIVE" ATTEMPTS TO SELECT SUCH A DRIVE.
*                  LBA2 LBA1 LBA0
SDDRV0         FCB $02, $20, $00 DRIVE0, SYSTEM DRIVE.
SDDRV1         FCB $02, $38, $00 DRIVE1,
SDDRV2         FCB $02, $50, $00 DRIVE2,
SDDRV3         FCB $02, $68, $00 DRIVE3,

* BASE BLOCK OF CURRENTLY-SELECTED DRIVE. SET BY COPYING A TRIPLET
* FROM ONE OF SDDRV0-3 ABOVE. DRIVE0 IS SELECTED AT FLEX BOOT TIME.
* A CALL TO "DRIVE" CAN SELECT SOME OTHER TRIPLET
SDDRV          FCB $FF, $00, $00 CURRENT DRIVE

* SCRATCH USED BY "LDSDADRS" (STORES LBA0, LBA1, LBA2 TEMPORARILY)
SDTMP          FCB $00, $00, $00


*******************************************************************
* SUBROUTINE READ
*
* READ ONE SECTOR
* A: TRACK
* B: SECTOR
* X: WHERE TO STORE THE DATA (256 BYTES)
* CAN DESTROY A,B,X,U MUST PRESERVE Y.
* EXIT WITH Z=1 IF NO ERROR, Z=0 IF ERROR. IF ERROR, B HAS ERROR CODE
READ           BSR LDSDADRS     CONVERT T,S TO BLOCK AND LOAD HARDWARE REGISTERS

* ISSUE THE READ COMMAND TO THE SDCARD CONTROLLER
               CLRA
               STA  SDCTL
* TRANSFER 512 BYTES, WAITING FOR EACH IN TURN. ONLY WANT 256
* OF THEM - DISCARD THE REST
               CLRB             ZERO IS LIKE 256
SDBIZ          LDA SDCTL
               CMPA #$E0
               BNE SDBIZ        BYTE NOT READY
               LDA SDDATA       GET BYTE
               STA ,X+          STORE IN SECTOR BUFFER
               DECB
               BNE SDBIZ        NEXT

SDBIZ2         LDA SDCTL        B IS ALREADY ZERO (LIKE 256)
               CMPA #$E0
               BNE SDBIZ2       BYTE NOT READY
               LDA SDDATA       GET BYTE (BUT DO NOTHING WITH IT)
               DECB
               BNE SDBIZ2       NEXT

               CLRA             SET Z TO INDICATE SUCCESSFUL COMPLETION
               RTS


*******************************************************************
* HELPER SUBROUTINE LDSDADRS
*
* SET SDLBA2 SDLBA1 SDLBA0 FOR NEXT SD OPERATION
* DISK GEOMETRY IS HARD-CODED. ASSUMED TO USE 72 SECTORS PER TRACK
* AND TO HAVE THE SAME NUMBER ON TRACK 0.
* CONVERT FROM TRACK, SECTOR TO BLOCK AND ADD TO THE START BLOCK.
* COMPUTE LBA0 + 256*LBA1 + 256*256*LBA2 + A*72 + B - 1
*
* A: TRACK
* B: SECTOR
* RETURN WITH SDCONTROLLER SDLBA0-2 REGISTERS SET UP
* CAN DESTROY A,B,CC.
LDSDADRS       PSHS X           PRESERVE IT
               LDX  #SDTMP      SCRATCH AREA FOR COMPUTATION

* ADD IN THE "+B - 1" PART TO THE IMAGE BASE OF THE CURRENT DRIVE
               SUBB #1          SECTOR->OFFSET. EG: SECTOR 1 IS AT OFFSET 0
               ADDB SDDRV+2     ADD SECTOR OFFSET TO LBA0 OF IMAGE BASE, CURRENT DRIVE
               STB  ,X+         STORE IN SCRATCH SPACE
               LDB  #0
               ADCB SDDRV+1     RIPPLE CARRY TO LBA1 OF IMAGE BASE, CURRENT DRIVE
               STB  ,X+         AND STORE
               LDB  #0
               ADCB SDDRV+0     RIPPLE CARRY TO LBA2 OF IMAGE BASE, CURRENT DRIVE
               STB  ,X          AND STORE
               LEAX -2,X        X BACK TO START OF BUFFER

* ADD IN THE "A*72" PART AND STORE TO WRITE-ONLY HARDWARE REGISTERS
* [NAC HACK 2015May26] MAYBE PUT THE 72 IN RAM SO WE CAN SUPPORT OTHER GEOMETRIES/DD-DISKS
               LDB  #72
               MUL  A B
               ADDB ,X+         ADD LS BYTE IN B TO LBA0+SECTOR
               STB  SDLBA0      LS BYTE DONE
               ADCA ,X+         ADD MS BYTE IN A TO LBA1+CARRY
               STA  SDLBA1      AND STORE
               LDA  #0
               ADCA ,X          RIPPLE CARRY TO LAST BYTE
               STA  SDLBA2      AND STORE
               PULS X
               RTS


*******************************************************************
* SUBROUTINE WRITE
*
* WRITE ONE SECTOR
WRITE          BSR LDSDADRS     CONVERT T,S TO BLOCK AND LOAD HARDWARE REGISTERS

* ISSUE THE WRITE COMMAND TO THE SDCARD CONTROLLER
               LDA  #1
               STA  SDCTL
* TRANSFER 512 BYTES, WAITING FOR EACH IN TURN. ONLY HAVE 256
* BYTES SO TRANSFER THEM TWICE
               PSHS X           PRESERVE DATA SOURCE
               CLRB             ZERO IS LIKE 256
SDWBIZ         LDA SDCTL
               CMPA #$A0
               BNE SDWBIZ       SPACE NOT AVAILABLE
               LDA ,X+          GET BYTE FROM BUFFER
               STA SDDATA       STORE TO SD
               DECB
               BNE SDWBIZ       NEXT

               PULS X           RESTORE DATA SOURCE FOR 2ND COPY
SDWBIZ2        LDA SDCTL        B IS ZERO (LIKE 256)
               CMPA #$A0
               BNE SDWBIZ2      SPACE NOT AVAILABLE
               LDA ,X+          GET BYTE FROM BUFFER
               STA SDDATA       STORE TO SD
               DECB
               BNE SDWBIZ2      NEXT

               CLRA             SET Z TO INDICATE SUCCESSFUL COMPLETION
               RTS


*******************************************************************
* SUBROUTINE DRIVE
*
* SELECT THE SPECIFIED DRIVE. THE DRIVE IS SPECIFIED IN AN FCB
* POINTED TO BY THE CONTENTS OF THE X REGISTER.
* X: FCB ADDRESS (3,X CONTAINS THE DRIVE NUMBER, 0-3)
* CAN DESTROY A B
* DOCUMENTATION SAYS X CAN BE DESTROYED BUT SOURCE CODE SHOWS THAT
* X MUST BE PRESERVED (EG: READS4 LOADS X WITH FCBSTR THEN CALLS
* DRIVE, GETCUR AND READ IN SUCCESSION ASSUMING X IS PRESERVED)
* EXIT SUCCESS: Z=1, C=0
* EXIT ERROR:   Z=0, C=1, B=$0F (NON-EXISTENT DRIVE)
DRV
               LDA 3,X          DRIVE NUMBER
               CMPA #3          ENSURE IT'S <4
               BGT NODRV        NO GOOD!

               PSHS X           SAVE FCB
               LDX #SDDRV0      LIST OF DRIVE OFFSETS
               LDB #3           SIZE OF TABLE ENTRY
               MUL              OFFSET FROM SDDRV0
*                               RESULT IS 0-12 SO MUST BE WHOLLY IN B
               ABX              ADDRESS OF LBA2 FOR REQUESTED DRIVE
               LDA 0,X          GET LBA2 VALUE
               CMPA #$FF
               BEQ NODRV1       DRIVE NOT AVAILABLE
               STA SDDRV+0      STORE LBA2
               LDA 1,X          GET LBA1 VALUE
               STA SDDRV+1      STORE LBA1
               LDA 2,X          GET LBA0 VALUE
               STA SDDRV+2      STORE LBA0
               PULS X           RESTORE FCB
               CLRA             Z=1, C=0 TO INDICATE SUCCESSFUL COMPLETION
               RTS

NODRV1         PULS X           RESTORE FCB
NODRV          CLRB
               ADDB #$0F        ERROR. Z=0
               ORCC #$01               C=1
               RTS


*******************************************************************
* SUBROUTINE VERIFY
*
* VERIFY ONE SECTOR
* RELIES ON HARDWARE VERIFICATION (CRC CHECK) WHICH IS NOT AVAILABLE
* SO WE JUST PRETEND THAT EVERYTHING WAS FINE
* CAN DESTROY A,B,X,CC


*******************************************************************
* SUBROUTINE RESTORE
*
* SEEK TO TRACK 0 ON SPECIFIED DRIVE. NO-OP ON SD CONTROLLER.


*******************************************************************
* SUBROUTINE CHKRDY
*
* CHECK FOR DRIVE READY. NO-OP ON SD CONTROLLER
* RETURN WITH Z !C


*******************************************************************
* SUBROUTINE SEEK
*
* SEEK TO THE SPECIFIED TRACK. NO-OP ON SD CONTROLLER
VERIFY
RST
CHKRDY
SEEK           CLRA
               RTS


*******************************************************************
* SUBROUTINE INIT AND WARM
*
* INITIALIZE HARDWARE AND WORKSPACE
* ANY INIT NEEDED FOR MULTICOMP WAS DONE LONG BEFORE THIS
INIT           LDX #CURDRV      POINT TO VARIABLES
               LDB #5           NUMBER OF BYTES TO CLEAR
INIT2          CLR 0,X+         CLEAR A BYTE
               DECB
               BNE INIT2        LOOP TIL DONE
WARM           RTS              NOTHING NEEDED FOR WARM START

               END

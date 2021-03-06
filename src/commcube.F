c-----------------------------------------------------------------------
      SUBROUTINE RRING(WORK,X,N,IRG)
      DIMENSION X(N),WORK(N)
C
C     Pass data X around a ring network, and receive corresponding
C     data into WORK.
C
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
C
      IF (IRG.EQ.1) THEN
         CALL COPY(WORK,X,N)
      ELSE
         LEN   = WDSIZE*N
         LEN2  = 2*LEN
         ITYPE = 6000+NID
         CALL CSEND(ITYPE,WORK,LEN,LFTNBR,NULLPID)
         JTYPE = 6000+RGTNBR
         CALL CRECV(JTYPE,WORK,LEN2)
      ENDIF
      RETURN
      END
      SUBROUTINE CRING(WORK,X,N,IRG)
C
C     Pass data X around a ring network, and receive corresponding
C     data into WORK.
C
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
      DIMENSION X(N),WORK(N)
      CHARACTER*1 X,WORK
C
      PARAMETER (LTOT2=LX1*LY1*LZ1*LELT*2)
      PARAMETER (LTOT8=LTOT2*4)
      COMMON /CTMP0/ CW1(LTOT8)
      CHARACTER*1    CW1
      DIMENSION      RW1(LTOT2)
      EQUIVALENCE   (RW1,CW1)
C
      IF (IRG.EQ.1) THEN
         CALL CHCOPY(WORK,X,N)
      ELSE
C
C        enough work space?
         IF (N.GT.LTOT8) THEN
            WRITE(6,100) NID,N,LTOT8
  100       FORMAT(2X,I5,
     $     'WARNING: In routine CRING, not enough work space.'
     $     ,/,2X,'Required # of words:',I7,' Supplied:',I7)
            CALL EXITT
         ENDIF
C
         CALL CHCOPY(CW1,WORK,N)
         LEN   = N
         LEN2  = 2*LEN
         ITYPE = 6000+NID
         CALL CSEND(ITYPE,RW1,LEN,LFTNBR,NULLPID)
         JTYPE = 6000+RGTNBR
         CALL CRECV(JTYPE,RW1,LEN2)
         ICNT = INFOCOUNT()
         CALL CHCOPY(WORK,CW1,ICNT)
      ENDIF
      RETURN
      END
      SUBROUTINE IRING(WORK,X,N,IRG)
      INTEGER X(N),WORK(N)
C
C     Pass data X around a ring network, and receive corresponding
C     data into WORK.
C
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
C
      IF (IRG.EQ.1) THEN
         CALL ICOPY(WORK,X,N)
      ELSE
         LEN   = ISIZE*N
         LEN2  = 2*LEN
         ITYPE = 6000+NID
         CALL CSEND(ITYPE,WORK,LEN,LFTNBR,NULLPID)
         JTYPE = 6000+RGTNBR
         CALL CRECV(JTYPE,WORK,LEN2)
      ENDIF
      RETURN
      END
c-----------------------------------------------------------------------
      SUBROUTINE OGOP( X, WORK, OP, N)
c
c  Global vector commutative operation using spanning tree.
c
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
      INCLUDE 'INPUT'
C
      REAL X(N), WORK(N)
      CHARACTER*3 OP
      DIMENSION ORGNL(100)
C
      INTEGER BIT, BYTES, CNT, DIFF, SPSIZE, I, 
     *   PARENT, TROOT, XOR, ROOT
      LOGICAL IFGOT
C
c  All participating processes must have the same process id (PID).
c
c  Input..
c
c    X         the input vector to be used in the operation.  
c    N         the length of the vector.
c    OP        '+'  sum
c              '*'  product
c              'M'  maximum
c              'm'  minimum
c
c  Output..
c
c    X         for all processes, X contains the desired result.
c
c  Workspace
c
c    WORK      used to receive other contributions.  
c
c  Calls:  MYNODE, RECVW, SENDW, XOR
c
c
c     Find temporary root (either the real root, or the lowest
c     numbered node in the active subcube--found by zeroing the
c     CD lowest bits in NID).
c
      IF (IFGPRNT) THEN
         A1=0.0
         TIME1=SECOND(A1)
         N100=MIN(9,N)
         CALL COPY(ORGNL,X,N100)
      ENDIF
      TYPE  = TYPE+100
      IF (TYPE.GT.99924000) TYPE=TYPE-92000
      TYPER = TYPE-1
C
      IF (NP.GT.1) THEN
C
C        perform global operation...
C
      ROOT  = NODE0
      TROOT = MAX0((NID/NP)*NP, ROOT)
c
      DIFF = XOR(NID,TROOT)
      IF (DIFF .GE. NP) THEN
         WRITE(6,*) NID,'GOP: CALLED BY NON PARTICIPANT'
         RETURN
      ENDIF
c
c     Accumulate contributions from children, if any
c
      BIT = NP/2
      BYTES = WDSIZE*N
    5 IF (BIT .LE. DIFF) GO TO 20
         CALL CRECV(   TYPE,WORK,BYTES               )
         CNT = INFOCOUNT()
         IF (CNT .GT. BYTES) 
     $      WRITE(6,*) NID,CNT,'GOP: LONG MESSAGE'
         IF (CNT .LT. BYTES) THEN
            WRITE(6,8) TYPE,BYTES,CNT,BIT,NID
    8       FORMAT('GOP: SHORT',5I6)
         ENDIF
         IF (OP.EQ.'+  '.AND.N.GE.20) THEN
            CALL ADD2(X,WORK,N)
         ELSEIF (OP.EQ.'SUM'.AND.N.GE.20) THEN
            CALL ADD2(X,WORK,N)
         ELSEIF (OP.EQ.'MUL'.AND.N.GE.20) THEN
            CALL COL2(X,WORK,N)
         ELSEIF (OP.EQ.'*  '.AND.N.GE.20) THEN
            CALL COL2(X,WORK,N)
         ELSEIF ( (OP.EQ.'m  '.OR.OP.EQ.'M  ') .OR.
     $            (OP.EQ.'MAX'.OR.OP.EQ.'MIN') .OR.
     $            (OP.EQ.'MXA'.OR.OP.EQ.'MNA') .OR.
     $            (OP.EQ.'SUM'.OR.OP.EQ.'MUL') .OR.
     $            (OP.EQ.'+  '.OR.OP.EQ.'*  ')    ) THEN
            DO 10 I = 1, N
               IF (OP .EQ. 'MXA'.and.ABS(WORK(I)).GT.ABS(X(I)))
     $            X(I) = WORK(I)
               IF (OP .EQ. 'MNA'.and.ABS(WORK(I)).LT.ABS(X(I)))
     $            X(I) = WORK(I)
               IF (OP .EQ. 'MUL')
     $            X(I) = X(I) * WORK(I)
               IF (OP .EQ. 'SUM')
     $            X(I) = X(I) + WORK(I)
               IF (OP .EQ. '+  ') X(I) = X(I) + WORK(I)
               IF (OP .EQ. '*  ') X(I) = X(I) * WORK(I)
               IF (OP .EQ. 'M  ' .OR. OP .EQ. 'MAX')
     $            X(I) = MAX(X(I),WORK(I))
               IF (OP .EQ. 'm  ' .OR. OP .EQ. 'MIN')
     $            X(I) = MIN(X(I),WORK(I))
   10       CONTINUE
         ELSEIF (OP .EQ. 'ISm') THEN
C           ISAMIN
C           Isolate first occurance of MIN(WORK(I))
            DO 11 I=1,N/2,2
c              IF (WORK(I+1).LT.X(I+1)) X(I)=WORK(I)
               IF (WORK(I+1).LE.X(I+1)) THEN
                  IF (WORK(I+1).LT.X(I+1)) THEN
                     X(I)  =WORK(I)
                     X(I+1)=WORK(I+1)
                  ELSE
                     X(I)=MIN(X(I),WORK(I))
                  ENDIF
c                 write(6,88) nid,work(i+1),x(i+1),work(i),x(i),i
   88             format(' ISm:',i4,4E12.4,I5)
               ENDIF
   11       CONTINUE
         ELSEIF (OP .EQ. 'ISM') THEN
C           ISAMAX
            DO 12 I=1,N/2,2
c              IF (WORK(I+1).GT.X(I+1)) X(I)=WORK(I)
               IF (WORK(I+1).GE.X(I+1)) THEN
                  IF (WORK(I+1).GT.X(I+1)) THEN
                     X(I)=WORK(I)
                     X(I+1)=WORK(I+1)
                  ELSE
                     X(I)=MIN(X(I),WORK(I))
                  ENDIF
               ENDIF
   12       CONTINUE
         ENDIF
         BIT = BIT/2
      GOTO 5
c
c     Pass result back to parent
c
   20 CONTINUE
C
      IF (BIT .NE. 0) THEN
         PARENT = XOR(NID, BIT)
         CALL CSEND(TYPE,X,BYTES,PARENT,NULLPID)
      ELSE
         IF (ROOT.LT.0) CALL CSEND(TYPE,X,BYTES,MANAGER,NULLPID)
      ENDIF
C
C     AWAIT FINAL ANSWER FROM NODE 0
C
      if (param(183).eq.0) then
C
        LEVEL=NP/2
        IFGOT=.FALSE.
        IF (NID.EQ.ROOT) IFGOT=.TRUE.
C
        DO 1000 I=1,CD
         IF (IFGOT) THEN
            JNID=NID+LEVEL
c           write(6,*) nid,'sending to :',jnid,i,level
            CALL CSEND(TYPER,X,BYTES,JNID,NULLPID)
         ELSEIF (MOD(NID,LEVEL).EQ.0) THEN
            CALL CRECV(TYPER,X,BYTES)
            IFGOT=.TRUE.
         ENDIF
         LEVEL=LEVEL/2
 1000   CONTINUE
C
      ELSE
        IF (NID.EQ.ROOT) THEN
           CALL CSEND ( TYPE,X,BYTES,ALLNODES,NULLPID)
        ELSE
           CALL CRECV ( TYPE,X,BYTES)
        ENDIF
      ENDIF
C
C
C     End of parallel section....
      ENDIF
C
C     Diagnostics?
C
      IF (IFGPRNT) THEN
         TIME2=SECOND(A1)
         GTIME=TIME2-TIME1
         ETIME=TIME2-TIME0
         DO 100 I=1,N100
            WRITE(6,101) NID,OP,TYPE,I,N,X(I),ORGNL(I),ETIME,GTIME
  100    CONTINUE
  101    FORMAT(I3,' GOP ',A3,I6,2I2,4G12.4)
      ENDIF
      RETURN
      END
      SUBROUTINE DGOP( X, WORK, OP, N)
c
c  Global vector commutative operation using spanning tree.
c
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
      INCLUDE 'INPUT'
C
      REAL*8 X(N), WORK(N)
      CHARACTER*3 OP
C
      INTEGER BIT, BYTES, CNT, DIFF, SPSIZE, I, 
     *   PARENT, TROOT, XOR, ROOT
      LOGICAL IFGOT
C
c  All participating processes must have the same process id (PID).
c
c  Input..
c
c    X         the input vector to be used in the operation.  
c    N         the length of the vector.
c    OP        '+'  sum
c              '*'  product
c              'M'  maximum
c              'm'  minimum
c
c  Output..
c
c    X         for all processes, X contains the desired result.
c
c  Workspace
c
c    WORK      used to receive other contributions.  
c
c  Calls:  MYNODE, RECVW, SENDW, XOR
c
c
      TYPE  = TYPE+100
      IF (TYPE.GT.99924000) TYPE=TYPE-92000
      TYPER = TYPE-1
      IF (NP.EQ.1) RETURN
C
C        perform global operation...
C
      ROOT  = NODE0
      TROOT = MAX0((NID/NP)*NP, ROOT)
c
      DIFF = XOR(NID,TROOT)
      IF (DIFF .GE. NP) THEN
         WRITE(6,*) NID,'DGOP: CALLED BY NON PARTICIPANT'
         RETURN
      ENDIF
c
c     Accumulate contributions from children, if any
c
      BYTES = 8*N
C
      level2=1
    5 continue
      level=level2
      level2=level+level
      IF (mod(nid,level2).ne.0) GO TO 20
C
         CALL CRECV(   TYPE,WORK,BYTES               )
C
C
         CNT = INFOCOUNT()
         IF (CNT .GT. BYTES) 
     $      WRITE(6,*) NID,CNT,'DGOP: LONG MESSAGE'
         IF (CNT .LT. BYTES) THEN
            WRITE(6,8) TYPE,BYTES,CNT,level,NID
    8       FORMAT('DGOP: SHORT',5I6)
         ENDIF
C
C
         IF     ( (OP.EQ.'m  '.OR.OP.EQ.'M  ') .OR.
     $            (OP.EQ.'MAX'.OR.OP.EQ.'MIN') .OR.
     $            (OP.EQ.'MXA'.OR.OP.EQ.'MNA') .OR.
     $            (OP.EQ.'SUM'.OR.OP.EQ.'MUL') .OR.
     $            (OP.EQ.'+  '.OR.OP.EQ.'*  ')    ) THEN
            DO 10 I = 1, N
               IF (OP .EQ. 'MXA'.and.ABS(WORK(I)).GT.ABS(X(I)))
     $            X(I) = WORK(I)
               IF (OP .EQ. 'MNA'.and.ABS(WORK(I)).LT.ABS(X(I)))
     $            X(I) = WORK(I)
               IF (OP .EQ. 'MUL')
     $            X(I) = X(I) * WORK(I)
               IF (OP .EQ. 'SUM')
     $            X(I) = X(I) + WORK(I)
               IF (OP .EQ. '+  ') X(I) = X(I) + WORK(I)
               IF (OP .EQ. '*  ') X(I) = X(I) * WORK(I)
               IF (OP .EQ. 'M  ' .OR. OP .EQ. 'MAX')
     $            X(I) = MAX(X(I),WORK(I))
               IF (OP .EQ. 'm  ' .OR. OP .EQ. 'MIN')
     $            X(I) = MIN(X(I),WORK(I))
   10       CONTINUE
         ELSEIF (OP .EQ. 'ISm') THEN
C           ISAMIN
C           Isolate first occurance of MIN(WORK(I))
            DO 11 I=1,N/2,2
c              IF (WORK(I+1).LT.X(I+1)) X(I)=WORK(I)
               IF (WORK(I+1).LE.X(I+1)) THEN
                  IF (WORK(I+1).LT.X(I+1)) THEN
                     X(I)  =WORK(I)
                     X(I+1)=WORK(I+1)
                  ELSE
                     X(I)=MIN(X(I),WORK(I))
                  ENDIF
               ENDIF
   11       CONTINUE
         ELSEIF (OP .EQ. 'ISM') THEN
C           ISAMAX
            DO 12 I=1,N/2,2
c              IF (WORK(I+1).GT.X(I+1)) X(I)=WORK(I)
               IF (WORK(I+1).GE.X(I+1)) THEN
                  IF (WORK(I+1).GT.X(I+1)) THEN
                     X(I)=WORK(I)
                     X(I+1)=WORK(I+1)
                  ELSE
                     X(I)=MIN(X(I),WORK(I))
                  ENDIF
               ENDIF
   12       CONTINUE
         ENDIF
      IF (LEVEL2.LT.NP) GOTO 5
c
c     Pass result back to parent
c
   20 CONTINUE
C
      IF (nid .NE. 0) THEN
         PARENT = nid-level
         CALL CSEND(TYPE,X,BYTES,PARENT,NULLPID)
      ENDIF
C
C---------------------------------------------------------------
C     AWAIT FINAL ANSWER FROM NODE 0
C---------------------------------------------------------------
C
      IF (PARAM(183).EQ.0) THEN
C
C         We do this via log_2 fan out
C
          LEVEL=NP/2
          IFGOT=.FALSE.
          IF (NID.EQ.ROOT) IFGOT=.TRUE.
C
          DO 1000 I=1,CD
           IF (IFGOT) THEN
              JNID=NID+LEVEL
              CALL CSEND(TYPER,X,BYTES,JNID,NULLPID)
           ELSEIF (MOD(NID,LEVEL).EQ.0) THEN
              CALL CRECV(TYPER,X,BYTES)
              IFGOT=.TRUE.
           ENDIF
           LEVEL=LEVEL/2
 1000     CONTINUE
C
      ELSE
C
C         Use global broadcast
C
          IF (NID.EQ.ROOT) THEN
             CALL CSEND ( TYPE,X,BYTES,ALLNODES,NULLPID)
          ELSE
             CALL CRECV ( TYPE,X,BYTES)
          ENDIF
      ENDIF
C
C     End of parallel section....
C
      RETURN
      END
      SUBROUTINE IGOP( X, WORK, OP, N)
c
c  Global vector commutative operation using spanning tree.
c
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
      INTEGER ORGNL(100)
C
      INTEGER X(N), WORK(N)
      CHARACTER*3 OP
C
c  All participating processes must have the same process id (PID).
c
c  Input..
c
c    X         the input vector to be used in the operation.  
c    N         the length of the vector.
c    OP        '+'  sum
c              '*'  product
c              'M'  maximum
c              'm'  minimum
c
c  Output..
c
c    X         for all processes, X contains the desired result.
c
c  Workspace
c
c    WORK      used to receive other contributions.  
c
c  Calls:  MYNODE, RECVW, SENDW, XOR
c
      INTEGER BIT, BYTES, CNT, DIFF, SPSIZE, I, 
     *   PARENT, TROOT, XOR, ROOT
c
c     Find temporary root (either the real root, or the lowest
c     numbered node in the active subcube--found by zeroing the
c     CD lowest bits in NID).
c
      IF (IFGPRNT) THEN
         A1=0.0
         TIME1=SECOND(A1)
         N100=MIN(9,N)
         CALL ICOPY(ORGNL,X,N100)
      ENDIF
      TYPE = TYPE+100
      IF (TYPE.GT.99924000) TYPE=TYPE-92000
      TYPER = TYPE-1
C
      IF (NP.GT.1) THEN
C
C        perform global operation...
C
      ROOT  = NODE0
      TROOT = MAX0((NID/NP)*NP, ROOT)
c
      DIFF = XOR(NID,TROOT)
      IF (DIFF .GE. NP) THEN
         WRITE(6,*) NID,'GOP: CALLED BY NON PARTICIPANT'
         RETURN
      ENDIF
c
c     Accumulate contributions from children, if any
c
      BIT = NP/2
      BYTES = ISIZE*N
    5 IF (BIT .LE. DIFF) GO TO 20
         CALL CRECV(   TYPE,WORK,BYTES               )
         CNT = INFOCOUNT()
         IF (CNT .GT. BYTES) 
     $      WRITE(6,*) NID,CNT,'GOP: LONG MESSAGE'
         IF (CNT .LT. BYTES) THEN
            WRITE(6,8) TYPE,BYTES,CNT,BIT,NID,op
    8       FORMAT('IGOP: SHORT',5I6,1x,a3)
         ENDIF
         IF ( (OP.EQ.'m  '.OR.OP.EQ.'M  ') .OR.
     $        (OP.EQ.'MXA'.OR.OP.EQ.'MNA') .OR.
     $        (OP.EQ.'SUM'.OR.OP.EQ.'MUL') .OR.
     $        (OP.EQ.'+  '.OR.OP.EQ.'*  ') ) THEN
            DO 10 I = 1, N
               IF (OP .EQ. 'MXA'.and.ABS(WORK(I)).GT.ABS(X(I)))
     $            X(I) = WORK(I)
               IF (OP .EQ. 'MNA'.and.ABS(WORK(I)).LT.ABS(X(I)))
     $            X(I) = WORK(I)
               IF (OP .EQ. 'MUL')
     $            X(I) = X(I) * WORK(I)
               IF (OP .EQ. 'SUM')
     $            X(I) = X(I) + WORK(I)
               IF (OP .EQ. '+  ') X(I) = X(I) + WORK(I)
               IF (OP .EQ. '*  ') X(I) = X(I) * WORK(I)
               IF (OP .EQ. 'M  ') X(I) = MAX(X(I),WORK(I))
               IF (OP .EQ. 'm  ') X(I) = MIN(X(I),WORK(I))
   10       CONTINUE
         ELSE
            IF (OP .EQ. 'COM') CALL COMBIN2(X,WORK,N)
         ENDIF
         BIT = BIT/2
      GO TO 5
c
c     Pass result back to parent
c
   20 CONTINUE
C
      IF (BIT .NE. 0) THEN
         PARENT = XOR(NID, BIT)
         CALL CSEND(TYPE,X,BYTES,PARENT,NULLPID)
      ELSE
         IF (ROOT.LT.0) CALL CSEND(TYPE,X,BYTES,MANAGER,NULLPID)
      ENDIF
C
C     AWAIT FINAL ANSWER FROM NODE 0
C
      IF (NID.EQ.ROOT) THEN
         CALL CSEND ( TYPE,X,BYTES,ALLNODES,NULLPID)
      ELSE
         CALL CRECV ( TYPE,X,BYTES)
      ENDIF
C
C     End of global operation
C
      ENDIF
C
C     Diagnostics?
C
      IF (IFGPRNT) THEN
         TIME2=SECOND(A1)
         GTIME=TIME2-TIME1
         ETIME=TIME2-TIME0
         DO 100 I=1,N100
            WRITE(6,101) NID,OP,TYPE,I,N,X(I),ORGNL(I),ETIME,GTIME
  100    CONTINUE
  101    FORMAT(I3,' IGOP ',A3,I6,2I2,2I12,2G12.4)
      ENDIF
      RETURN
      END
      INTEGER FUNCTION XOR(M,N)
c
c  If NOT running on a parallel processor, it is sufficient to 
c  have this routine return a value of XOR=1.
c
c  Pick one of the following:
c
c  UNIX 4.2, f77:
      XOR = OR(M,N)-AND(M,N)
c
c  Intel FTN286:
c     XOR = M.NEQV.N
c
c  Ryan-McFarland Fortran
C      XOR = IEOR(M,N)
c
c     XOR = 0
c     IF(M.EQ.1 .OR.  N.EQ.1) XOR=1
c     IF(M.EQ.0 .AND. N.EQ.0) XOR=0
c     IF(M.EQ.1 .AND. N.EQ.1) XOR=0
c     IF(M.GT.1 .OR.N.GT.1 .OR.M.LT.0.OR.N.LT.0) THEN
c        PRINT*,'ERROR IN XOR'
c        STOP
c     ENDIF
      RETURN
      END
      FUNCTION SECOND(A)
      REAL*8 DCLOCK
      SECOND=DCLOCK(A)
      RETURN
      END
      SUBROUTINE LBCAST(IFIF)
C
C  Broadcast logical variable to all processors.
C
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
      LOGICAL IFIF
C
      INTEGER MTYPE
      SAVE    MTYPE
      DATA    MTYPE /400/
C
      IF (NP.EQ.1) RETURN
C
      MTYPE=MTYPE-399
      MTYPE=MOD(MTYPE,6000)+400
      LEN=4
      ITEM=0
      IF (IFIF) ITEM=1
      IF (NID.EQ.NODE0) THEN
         CALL CSEND(MTYPE, ITEM, LEN, ALLNODES ,NULLPID)
      ELSE
         CALL CRECV(MTYPE, ITEM, LEN            )
      ENDIF
      IFIF=.FALSE.
      IF (ITEM.EQ.1) IFIF=.TRUE.
      RETURN
      END
C
      FUNCTION CPUTIME(DUMMY)
      REAL*8 cpu2,dclock
C
C     this function returns the cpu time in seconds
C
      cpu2=dclock()
      CPUTIME = cpu2
      RETURN
      END
C========================================================================
      subroutine bcast(buf,len)
      real*4 buf(1)
c
      logical ifgot
c
      include 'SIZE'
      include 'PARALLEL'
C
C     log_2 fan out
C
      LEVEL=NP/2
      IFGOT=.FALSE.
      IF (NID.EQ.0) IFGOT=.TRUE.
C
      typer = typer+1
c
      DO I=1,CD
         IF (IFGOT) THEN
            JNID=NID+LEVEL
            CALL CSEND(TYPER,X,BUF,JNID,NULLPID)
         ELSEIF (MOD(NID,LEVEL).EQ.0) THEN
            CALL CRECV(TYPER,X,BUF)
            IFGOT=.TRUE.
         ENDIF
         LEVEL=LEVEL/2
      ENDDO
c
c
      RETURN
      END
c-----------------------------------------------------------------------
      SUBROUTINE GOP( X, W, OP, N)
c
c  Global vector commutative operation using spanning tree.
c
      INCLUDE 'SIZE'
      INCLUDE 'PARALLEL'
      INCLUDE 'INPUT'
      INCLUDE 'CTIMER'
C
      REAL X(N), W(N)
      CHARACTER*3 OP
      DIMENSION ORGNL(100)
C
      INTEGER BIT, BYTES, CNT, DIFF, SPSIZE, I, 
     *   PARENT, TROOT, XOR, ROOT
      LOGICAL IFGOT
c
      if (icalld.eq.0) then
        tgop =0.0d0
        ngop =0
        icalld=1
      endif
      ngop = ngop + 1
      etime1=dclock()
c
      IF (OP.EQ.'+  ') THEN 
         call gdsum(x,n,w)
         tgop =tgop +(dclock()-etime1)
         return
      endif
C
      TYPE  = TYPE+100
      IF (TYPE.GT.99924000) TYPE=TYPE-92000
      TYPER = TYPE-1
      IF (NP.GT.1) THEN
         bytes = wdsize*n
         IF (n.eq.1) THEN
c
c            if (nid.eq.0) then 
c               write(6,*) nid,n,op,'calling logp ver. 1'
c            endif
c     
c     Use forest of trees
C
            level = 1
            itag = 0
            do l=1,cd
               jnid = mod(    nid+level , np )
               mrec = mod( np+nid-level , np ) + type
               msnd = nid + type
               call csend (msnd,x,bytes,jnid,nullpid)
               call crecv (mrec,w,bytes)
               level = 2*level
C
               IF (OP.EQ.'+  ') THEN
                  x(1) = x(1)+w(1)
               ELSEIF (OP .EQ. 'M  ') THEN
                  X(1) = MAX(X(1),W(1))
               ELSEIF (OP .EQ. 'm  ') THEN
                  X(1) = MIN(X(1),W(1))
               ELSEIF (OP .EQ. '*  ') THEN
                  x(1) = x(1)*w(1)
               ELSEIF (OP .EQ. 'MXA') THEN
                  if (ABS(W(1)).GT.ABS(X(1))) X(1) = W(1)
               ELSEIF (OP.EQ.'MNA') THEN
                  if (ABS(W(1)).LT.ABS(X(1))) X(1) = W(1)
               ELSE
                  if (nid.eq.0) write(6,*) nid,n,op,' is NOT ready!'
                  goto 901
               ENDIF
c
            enddo
c
         elseif (n.eq.2) then
c
c            if (nid.eq.0) then 
c               write(6,*) nid,n,op,'calling logp ver. 2'
c            endif
c     
c     Use forest of trees
C
            level = 1
            itag = 0
            do l=1,cd
               jnid = mod(    nid+level , np )
               mrec = mod( np+nid-level , np ) + type
               msnd = nid + type
               call csend (msnd,x,bytes,jnid,nullpid)
               call crecv (mrec,w,bytes)
               level = 2*level
C
               IF (OP.EQ.'+  ') THEN
                  x(1) = x(1)+w(1)
                  x(2) = x(2)+w(2)
               ELSEIF (OP .EQ. 'M  ') THEN
                  X(1) = MAX(X(1),W(1))
                  X(2) = MAX(X(2),W(2))
               ELSEIF (OP .EQ. 'm  ') THEN
                  X(1) = MIN(X(1),W(1))
                  X(2) = MIN(X(2),W(2))
               ELSEIF (OP .EQ. '*  ') THEN
                  x(1) = x(1)*w(1)
                  x(2) = x(2)*w(2)
               ELSEIF (OP .EQ. 'MXA') THEN
                  if (ABS(W(1)).GT.ABS(X(1))) X(1) = W(1)
                  if (ABS(W(2)).GT.ABS(X(2))) X(2) = W(2)
               ELSEIF (OP.EQ.'MNA') THEN
                  if (ABS(W(1)).LT.ABS(X(1))) X(1) = W(1)
                  if (ABS(W(2)).LT.ABS(X(2))) X(2) = W(2)
               ELSE
                  if (nid.eq.0) write(6,*) nid,n,op,' is NOT ready!'
                  goto 901
               ENDIF
c
            enddo
c
         elseif (OP.EQ.'+  '.and.n.lt.100) then
c
c            if (nid.eq.0) then 
c               write(6,*) nid,n,op,'calling logp ver. 3'
c            endif
c     
c     Use forest of trees
C
            level = 1
            itag = 0
            do l=1,cd
               jnid = mod(    nid+level , np )
               mrec = mod( np+nid-level , np ) + type
               msnd = nid + type
               call csend (msnd,x,bytes,jnid,nullpid)
               call crecv (mrec,w,bytes)
               level = 2*level
C
               do ii=1,n
                  x(ii) = x(ii)+w(ii)
               enddo
c
            enddo
c
         else
c     
c         Std. fan-in/fan-out
C
C
c            if (nid.eq.0) then 
c               write(6,*) nid,n,op,'calling 2logp ver.'
c            endif
c
 901        ROOT  = NODE0
            TROOT = MAX0((NID/NP)*NP, ROOT)
            DIFF = XOR(NID,TROOT)
c
c     Accumulate contributions from children, if any
            level2=1
 5          continue
            level=level2
            level2=level+level
            IF (mod(nid,level2).ne.0) GO TO 20
            CALL CRECV(  TYPE,W,BYTES               )
            IF (OP.EQ.'+  '.AND.N.GE.20) THEN
               CALL ADD2(X,W,N)
            ELSEIF (OP.EQ.'SUM'.AND.N.GE.20) THEN
               CALL ADD2(X,W,N)
            ELSEIF (OP.EQ.'MUL'.AND.N.GE.20) THEN
               CALL COL2(X,W,N)
            ELSEIF (OP.EQ.'*  '.AND.N.GE.20) THEN
               CALL COL2(X,W,N)
            ELSEIF ( (OP.EQ.'m  '.OR.OP.EQ.'M  ') .OR.
     $              (OP.EQ.'MAX'.OR.OP.EQ.'MIN') .OR.
     $              (OP.EQ.'MXA'.OR.OP.EQ.'MNA') .OR.
     $              (OP.EQ.'SUM'.OR.OP.EQ.'MUL') .OR.
     $              (OP.EQ.'+  '.OR.OP.EQ.'*  ')    ) THEN
               DO 10 I = 1, N
                  IF (OP .EQ. 'MXA'.and.ABS(W(I)).GT.ABS(X(I)))
     $                 X(I) = W(I)
                  IF (OP .EQ. 'MNA'.and.ABS(W(I)).LT.ABS(X(I)))
     $                 X(I) = W(I)
                  IF (OP .EQ. 'MUL')
     $                 X(I) = X(I) * W(I)
                  IF (OP .EQ. 'SUM')
     $                 X(I) = X(I) + W(I)
                  IF (OP .EQ. '+  ') X(I) = X(I) + W(I)
                  IF (OP .EQ. '*  ') X(I) = X(I) * W(I)
                  IF (OP .EQ. 'M  ' .OR. OP .EQ. 'MAX')
     $                 X(I) = MAX(X(I),W(I))
                  IF (OP .EQ. 'm  ' .OR. OP .EQ. 'MIN')
     $                 X(I) = MIN(X(I),W(I))
 10            CONTINUE
            ELSEIF (OP .EQ. 'ISm') THEN
C
C     ISAMIN
C               Isolate first occurance of MIN(W(I))
               DO 11 I=1,N/2,2
c     IF (W(I+1).LT.X(I+1)) X(I)=W(I)
                  IF (W(I+1).LE.X(I+1)) THEN
                     IF (W(I+1).LT.X(I+1)) THEN
                        X(I)  =W(I)
                        X(I+1)=W(I+1)
                     ELSE
                        X(I)=MIN(X(I),W(I))
                     ENDIF
c     write(6,88) nid,w(i+1),x(i+1),w(i),x(i),i
 88                  format(' ISm:',i4,4E12.4,I5)
                  ENDIF
 11            CONTINUE
            ELSEIF (OP .EQ. 'ISM') THEN
C     ISAMAX
               DO 12 I=1,N/2,2
c     IF (W(I+1).GT.X(I+1)) X(I)=W(I)
                  IF (W(I+1).GE.X(I+1)) THEN
                     IF (W(I+1).GT.X(I+1)) THEN
                        X(I)=W(I)
                        X(I+1)=W(I+1)
                     ELSE
                        X(I)=MIN(X(I),W(I))
                     ENDIF
                  ENDIF
 12            CONTINUE
            ENDIF
            IF (LEVEL2.LT.NP) GOTO 5
c     Pass result back to parent
 20         PARENT = nid-level
            IF (nid .NE. 0) CALL CSEND(TYPE,X,BYTES,PARENT,NULLPID)
C
C     await final answer from node 0
            IF (PARAM(183).EQ.0) THEN
C     We do this via log_2 fan out
               LEVEL=NP/2
               IFGOT=.FALSE.
               IF (NID.EQ.ROOT) IFGOT=.TRUE.
C
               DO I=1,CD
                  IF (IFGOT) THEN
                     JNID=NID+LEVEL
                     CALL CSEND(TYPER,X,BYTES,JNID,NULLPID)
                  ELSEIF (MOD(NID,LEVEL).EQ.0) THEN
                     CALL CRECV(TYPER,X,BYTES)
                     IFGOT=.TRUE.
                  ENDIF
                  LEVEL=LEVEL/2
               ENDDO
            ELSE
C     Use global broadcast
               IF (NID.EQ.ROOT) THEN
                  CALL CSEND ( TYPE,X,BYTES,ALLNODES,NULLPID)
               ELSE
                  CALL CRECV ( TYPE,X,BYTES)
               ENDIF
            ENDIF
         ENDIF
c
C     End of parallel section....
      ENDIF
C
      tgop =tgop +(dclock()-etime1)
      RETURN
      END
c-----------------------------------------------------------------------
      subroutine exitt
      include 'SIZE'
      include 'TOTAL'
      if (nid.eq.0) write(6,*) nid,'  quittin'
      call flush_io()
      call exit
      return
      end
c-----------------------------------------------------------------------
      subroutine csendx(MTYPE,BUF,LEN,JNID,JPID)
      include 'SIZE'
      include 'PARALLEL'
      real*4 buf(1)
      call csend(MTYPE,BUF,LEN,JNID,JPID)
      RETURN
      END

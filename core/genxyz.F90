!-----------------------------------------------------------------------
    subroutine arcsrf(xml,yml,zml,nxl,nyl,nzl,ie,isid)
    use size_m
    use geom
    use input
    use topol
    use wz_m

!     ....note..... CTMP1 is used in this format in several subsequent routines

    COMMON /CTMP1/ H(LX1,3,2),XCRVED(LX1),YCRVED(LY1),ZCRVED(LZ1) &
    , ZGML(LX1,3),WORK(3,LX1,LZ1)
    DIMENSION XML(NXL,NYL,NZL,1),YML(NXL,NYL,NZL,1),ZML(NXL,NYL,NZL,1)
    LOGICAL :: IFGLJ

    IFGLJ = .FALSE. 
    IF (IFAXIS .AND. IFRZER(IE) .AND. (ISID == 2 .OR. ISID == 4)) &
    IFGLJ = .TRUE. 

    PT1X  = XC(ISID,IE)
    PT1Y  = YC(ISID,IE)
    IF(ISID == 4) THEN
        PT2X = XC(1,IE)
        PT2Y = YC(1,IE)
    ELSE IF(ISID == 8) THEN
        PT2X = XC(5,IE)
        PT2Y = YC(5,IE)
    ELSE
        PT2X = XC(ISID+1,IE)
        PT2Y = YC(ISID+1,IE)
    ENDIF

!     Find slope of perpendicular
    RADIUS=CURVE(1,ISID,IE)
    GAP=SQRT( (PT1X-PT2X)**2 + (PT1Y-PT2Y)**2 )
    IF (ABS(2.0*RADIUS) <= GAP*1.00001) THEN
        write(6,10) RADIUS,ISID,IE,GAP
        10 FORMAT(//,2X,'ERROR: Too small a radius (',G11.3 &
        ,') specified for side',I2,' of element',I4,':  ' &
        ,G11.3,/,2X,'ABORTING during mesh generation.')
        call exitt
    ENDIF
    XS = PT2Y-PT1Y
    YS = PT1X-PT2X
!     Make length Radius
    XYS=SQRT(XS**2+YS**2)
!     Find Center
    DTHETA = ABS(ASIN(0.5*GAP/RADIUS))
    PT12X  = (PT1X + PT2X)/2.0
    PT12Y  = (PT1Y + PT2Y)/2.0
    XCENN  = PT12X - XS/XYS * RADIUS*COS(DTHETA)
    YCENN  = PT12Y - YS/XYS * RADIUS*COS(DTHETA)
    THETA0 = ATAN2((PT12Y-YCENN),(PT12X-XCENN))
    IF (IFGLJ) THEN
        FAC    = SIGN(1.0,RADIUS)
        THETA1 = THETA0 - FAC*DTHETA
        THETA2 = THETA0 + FAC*DTHETA
    ENDIF
!     Compute perturbation of geometry
    ISID1 = MOD1(ISID,4)
    IF (IFGLJ) THEN
        I1 = ISID/2
        I2 = 2 - ISID/4
        DO 15 IY=1,NYL
            ANG  = H(IY,2,I1)*THETA1 + H(IY,2,I2)*THETA2
            XCRVED(IY)=XCENN + ABS(RADIUS)*COS(ANG) &
            - (H(IY,2,I1)*PT1X + H(IY,2,I2)*PT2X)
            YCRVED(IY)=YCENN + ABS(RADIUS) * SIN(ANG) &
            - (H(IY,2,I1)*PT1Y + H(IY,2,I2)*PT2Y)
        15 END DO
    ELSE
        DO 20 IX=1,NXL
            IXT=IX
            IF (ISID1 > 2) IXT=NXL+1-IX
            R=ZGML(IX,1)
            IF (RADIUS < 0.0) R=-R
            XCRVED(IXT) = XCENN + ABS(RADIUS) * COS(THETA0 + R*DTHETA) &
            - ( H(IX,1,1)*PT1X + H(IX,1,2)*PT2X )
            YCRVED(IXT) = YCENN + ABS(RADIUS) * SIN(THETA0 + R*DTHETA) &
            - ( H(IX,1,1)*PT1Y + H(IX,1,2)*PT2Y )
        20 END DO
    ENDIF
!     Points all set, add perturbation to current mesh.
    ISID1 = MOD1(ISID,4)
    ISID1 = EFACE1(ISID1)
    IZT = (ISID-1)/4+1
    IYT = ISID1-2
    IXT = ISID1
    IF (ISID1 <= 2) THEN
        CALL ADDTNSR(XML(1,1,1,IE),H(1,1,IXT),XCRVED,H(1,3,IZT) &
        ,NXL,NYL,NZL)
        CALL ADDTNSR(YML(1,1,1,IE),H(1,1,IXT),YCRVED,H(1,3,IZT) &
        ,NXL,NYL,NZL)
    ELSE
        CALL ADDTNSR(XML(1,1,1,IE),XCRVED,H(1,2,IYT),H(1,3,IZT) &
        ,NXL,NYL,NZL)
        CALL ADDTNSR(YML(1,1,1,IE),YCRVED,H(1,2,IYT),H(1,3,IZT) &
        ,NXL,NYL,NZL)
    ENDIF
    return
    end subroutine arcsrf
!-----------------------------------------------------------------------
    subroutine setdef
!-------------------------------------------------------------------

!     Set up deformed element logical switches

!-------------------------------------------------------------------
    use size_m
    use input
    DIMENSION XCC(8),YCC(8),ZCC(8)
    DIMENSION INDX(8)
    REAL :: VEC(3,12)
    LOGICAL :: IFVCHK

    COMMON /FASTMD/ IFDFRM(LELT), IFFAST(LELT), IFH2, IFSOLV
    LOGICAL :: IFDFRM, IFFAST, IFH2, IFSOLV

!   Corner notation:

!                  4+-----+3    ^ Y
!                  /     /|     |
!                 /     / |     |
!               8+-----+7 +2    +----> X
!                |     | /     /
!                |     |/     /
!               5+-----+6    Z


    DO 10 IE=1,NELT
        IFDFRM(IE)= .FALSE. 
    10 END DO

    IF (IFMVBD) return

!     Force IFDFRM=.true. for all elements (for timing purposes only)

    IF (param(59) /= 0 .AND. nid == 0) &
    write(6,*) 'NOTE: All elements deformed , param(59) ^=0'
    IF (param(59) /= 0) return

!     Check against cases which won't allow for savings in HMHOLTZ

    INDX(1)=1
    INDX(2)=2
    INDX(3)=4
    INDX(4)=3
    INDX(5)=5
    INDX(6)=6
    INDX(7)=8
    INDX(8)=7

!     Check for deformation (rotation is acceptable).

    DO 500 IE=1,NELT
    
        call rzero(vec,36)
        IF (IF3D) THEN
            DO 100 IEDG=1,8
                IF(CCURVE(IEDG,IE) /= ' ') THEN
                    IFDFRM(IE)= .TRUE. 
                    GOTO 500
                ENDIF
            100 END DO
        
            DO 105 I=1,8
                XCC(I)=XC(INDX(I),IE)
                YCC(I)=YC(INDX(I),IE)
                ZCC(I)=ZC(INDX(I),IE)
            105 END DO
        
            DO 110 I=1,4
                VEC(1,I)=XCC(2*I)-XCC(2*I-1)
                VEC(2,I)=YCC(2*I)-YCC(2*I-1)
                VEC(3,I)=ZCC(2*I)-ZCC(2*I-1)
            110 END DO
        
            I1=4
            DO 120 I=0,1
                DO 120 J=0,1
                    I1=I1+1
                    I2=4*I+J+3
                    VEC(1,I1)=XCC(I2)-XCC(I2-2)
                    VEC(2,I1)=YCC(I2)-YCC(I2-2)
                    VEC(3,I1)=ZCC(I2)-ZCC(I2-2)
            120 END DO
        
            I1=8
            DO 130 I=5,8
                I1=I1+1
                VEC(1,I1)=XCC(I)-XCC(I-4)
                VEC(2,I1)=YCC(I)-YCC(I-4)
                VEC(3,I1)=ZCC(I)-ZCC(I-4)
            130 END DO
        
            DO 140 I=1,12
                VECLEN = VEC(1,I)**2 + VEC(2,I)**2 + VEC(3,I)**2
                VECLEN = SQRT(VECLEN)
                VEC(1,I)=VEC(1,I)/VECLEN
                VEC(2,I)=VEC(2,I)/VECLEN
                VEC(3,I)=VEC(3,I)/VECLEN
            140 END DO
        
        !        Check the dot product of the adjacent edges to see that it is zero.
        
            IFDFRM(IE)= .FALSE. 
            IF (  IFVCHK(VEC,1,5, 9)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,1,6,10)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,2,5,11)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,2,6,12)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,3,7, 9)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,3,8,10)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,4,7,11)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,4,8,12)  ) IFDFRM(IE)= .TRUE. 
        
        !      Check the 2D case....
        
        ELSE
        
            DO 200 IEDG=1,4
                IF(CCURVE(IEDG,IE) /= ' ') THEN
                    IFDFRM(IE)= .TRUE. 
                    GOTO 500
                ENDIF
            200 END DO
        
            DO 205 I=1,4
                XCC(I)=XC(INDX(I),IE)
                YCC(I)=YC(INDX(I),IE)
            205 END DO
        
            VEC(1,1)=XCC(2)-XCC(1)
            VEC(1,2)=XCC(4)-XCC(3)
            VEC(1,3)=XCC(3)-XCC(1)
            VEC(1,4)=XCC(4)-XCC(2)
            VEC(1,5)=0.0
            VEC(2,1)=YCC(2)-YCC(1)
            VEC(2,2)=YCC(4)-YCC(3)
            VEC(2,3)=YCC(3)-YCC(1)
            VEC(2,4)=YCC(4)-YCC(2)
            VEC(2,5)=0.0
        
            DO 220 I=1,4
                VECLEN = VEC(1,I)**2 + VEC(2,I)**2
                VECLEN = SQRT(VECLEN)
                VEC(1,I)=VEC(1,I)/VECLEN
                VEC(2,I)=VEC(2,I)/VECLEN
            220 END DO
        
        !        Check the dot product of the adjacent edges to see that it is zero.
        
            IFDFRM(IE)= .FALSE. 
            IF (  IFVCHK(VEC,1,3,5)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,1,4,5)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,2,3,5)  ) IFDFRM(IE)= .TRUE. 
            IF (  IFVCHK(VEC,2,4,5)  ) IFDFRM(IE)= .TRUE. 
        ENDIF
    500 END DO
    return
    end subroutine setdef
    LOGICAL FUNCTION IFVCHK(VEC,I1,I2,I3)

!     Take the dot product of the three components of VEC to see if it's zero.

    DIMENSION VEC(3,12)
    LOGICAL :: IFTMP

    IFTMP= .FALSE. 
    EPSM=1.0E-06

    DOT1=VEC(1,I1)*VEC(1,I2)+VEC(2,I1)*VEC(2,I2)+VEC(3,I1)*VEC(3,I2)
    DOT2=VEC(1,I2)*VEC(1,I3)+VEC(2,I2)*VEC(2,I3)+VEC(3,I2)*VEC(3,I3)
    DOT3=VEC(1,I1)*VEC(1,I3)+VEC(2,I1)*VEC(2,I3)+VEC(3,I1)*VEC(3,I3)

    DOT1=ABS(DOT1)
    DOT2=ABS(DOT2)
    DOT3=ABS(DOT3)
    DOT=DOT1+DOT2+DOT3
    IF (DOT > EPSM) IFTMP= .TRUE. 

    IFVCHK=IFTMP
    return
    END FUNCTION IFVCHK
!-----------------------------------------------------------------------
    subroutine gencoor (xm3,ym3,zm3)
!-----------------------------------------------------------------------

!     Generate xyz coordinates  for all elements.
!        Velocity formulation : mesh 3 is used
!        Stress   formulation : mesh 1 is used

!-----------------------------------------------------------------------
    use size_m
    use geom
    use input
    DIMENSION XM3(LX3,LY3,LZ3,1),YM3(LX3,LY3,LZ3,1),ZM3(LX3,LY3,LZ3,1)

!     Select appropriate mesh

    IF ( IFGMSH3 ) THEN
      write(*,*) "Oops: IFGMSH3"
!max        CALL GENXYZ (XM3,YM3,ZM3,NX3,NY3,NZ3)
    ELSE
        CALL GENXYZ (XM1,YM1,ZM1,NX1,NY1,NZ1)
    ENDIF

    return
    end subroutine gencoor
!-----------------------------------------------------------------------
    subroutine genxyz (xml,yml,zml,nxl,nyl,nzl)

    use size_m
    use geom
    use input
    use parallel
    use topol
    use wz_m

    real :: xml(nxl,nyl,nzl,1),yml(nxl,nyl,nzl,1),zml(nxl,nyl,nzl,1)

!     Note : CTMP1 is used in this format in several subsequent routines
    common /ctmp1/ h(lx1,3,2),xcrved(lx1),ycrved(ly1),zcrved(lz1) &
    , zgml(lx1,3),work(3,lx1,lz1)

    parameter (ldw=2*lx1*ly1*lz1)
    common /ctmp0/ w(ldw)

    character(1) :: ccv

#ifdef MOAB
! already read/initialized vertex positions
    if (ifmoab) return
#endif

!     Initialize geometry arrays with bi- triquadratic deformations
    call linquad(xml,yml,zml,nxl,nyl,nzl)


    do ie=1,nelt

        call setzgml (zgml,ie,nxl,nyl,nzl,ifaxis)
        call sethmat (h,zgml,nxl,nyl,nzl)

    !        Deform surfaces - general 3D deformations
    !                        - extruded geometry deformations
        nfaces = 2*ndim
        do iface=1,nfaces
            ccv = ccurve(iface,ie)
            if (ccv == 's') &
            call sphsrf(xml,yml,zml,iface,ie,nxl,nyl,nzl,work)
            if (ccv == 'e') &
            call gensrf(xml,yml,zml,iface,ie,nxl,nyl,nzl,zgml)
        enddo

        do isid=1,8
            ccv = ccurve(isid,ie)
            if (ccv == 'C') call arcsrf(xml,yml,zml,nxl,nyl,nzl,ie,isid)
        enddo

    enddo

!     call user_srf(xml,yml,zml,nxl,nyl,nzl)
!     call opcopy(xm1,ym1,zm1,xml,yml,zml)
!     call outpost(xml,yml,zml,xml,yml,'   ')
!     call exitt

    return
    end subroutine genxyz
!-----------------------------------------------------------------------
    subroutine sethmat(h,zgml,nxl,nyl,nzl)

    use size_m
    use input  ! if3d

    real :: h(lx1,3,2),zgml(lx1,3)

    do 10 ix=1,nxl
        h(ix,1,1)=(1.0-zgml(ix,1))*0.5
        h(ix,1,2)=(1.0+zgml(ix,1))*0.5
    10 END DO
    do 20 iy=1,nyl
        h(iy,2,1)=(1.0-zgml(iy,2))*0.5
        h(iy,2,2)=(1.0+zgml(iy,2))*0.5
    20 END DO
    if (if3d) then
        do 30 iz=1,nzl
            h(iz,3,1)=(1.0-zgml(iz,3))*0.5
            h(iz,3,2)=(1.0+zgml(iz,3))*0.5
        30 END DO
    else
        call rone(h(1,3,1),nzl)
        call rone(h(1,3,2),nzl)
    endif

    return
    end subroutine sethmat
!-----------------------------------------------------------------------
    subroutine setzgml (zgml,e,nxl,nyl,nzl,ifaxl)

    use size_m
    use geom
    use wz_m

    real :: zgml(lx1,3)
    integer :: e
    logical :: ifaxl

    call rzero (zgml,3*nx1)


    if (nxl == 3 .AND. .NOT. ifaxl) then
        do k=1,3
            zgml(1,k) = -1
            zgml(2,k) =  0
            zgml(3,k) =  1
        enddo
    elseif (ifgmsh3 .AND. nxl == nx3) then
      write(*,*) "Oops: IFGMSH3"
#if 0
        call copy(zgml(1,1),zgm3(1,1),nx3)
        call copy(zgml(1,2),zgm3(1,2),ny3)
        call copy(zgml(1,3),zgm3(1,3),nz3)
        if (ifaxl .AND. ifrzer(e)) call copy(zgml(1,2),zam3,ny3)
#endif
    elseif (nxl == nx1) then
        call copy(zgml(1,1),zgm1(1,1),nx1)
        call copy(zgml(1,2),zgm1(1,2),ny1)
        call copy(zgml(1,3),zgm1(1,3),nz1)
        if (ifaxl .AND. ifrzer(e)) call copy(zgml(1,2),zam1,ny1)
    else
        call exitti('ABORT setzgml! $',nxl)
    endif

    return
    end subroutine setzgml
!-----------------------------------------------------------------------
    subroutine sphsrf(xml,yml,zml,ifce,ie,nx,ny,nz,xysrf)

!     5 Aug 1988 19:29:52

!     Program to generate spherical shell elements for NEKTON
!     input.  Paul F. Fischer

    use size_m
    use input
    use topol
    use wz_m
    DIMENSION XML(NX,NY,NZ,1),YML(NX,NY,NZ,1),ZML(NX,NY,NZ,1)
    DIMENSION XYSRF(3,NX,NZ)

    COMMON /CTMP1/ H(LX1,3,2),XCRVED(LX1),YCRVED(LY1),ZCRVED(LZ1) &
    , ZGML(LX1,3),WORK(3,LX1,LZ1)
    COMMON /CTMP0/ XCV(3,2,2),VN1(3),VN2(3) &
    ,X1(3),X2(3),X3(3),DX(3)
    DIMENSION IOPP(3),NXX(3)


!     These are representative nodes on a given face, and their opposites

    integer :: cface(2,6)
    save    cface
    data    cface / 1,4 , 2,1 , 3,2 , 4,3 , 1,5 , 5,1 /
    real ::    vout(3),vsph(3)
    logical :: ifconcv


!     Determine geometric parameters

    NXM1 = NX-1
    NYM1 = NY-1
    NXY  = NX*NZ
    NXY3 = 3*NX*NZ
    XCTR   = CURVE(1,IFCE,IE)
    YCTR   = CURVE(2,IFCE,IE)
    ZCTR   = CURVE(3,IFCE,IE)
    RADIUS = CURVE(4,IFCE,IE)
    IFACE  = EFACE1(IFCE)

!     Generate (normalized) corner vectors XCV(1,i,j):

    CALL CRN3D(XCV,XC(1,IE),YC(1,IE),ZC(1,IE),CURVE(1,IFCE,IE),IFACE)

!     Generate edge vectors on the sphere RR=1.0,
!     for (r,s) = (-1,*),(1,*),(*,-1),(*,1)

    CALL EDG3D(XYSRF,XCV(1,1,1),XCV(1,1,2), 1, 1, 1,NY,NX,NY)
    CALL EDG3D(XYSRF,XCV(1,2,1),XCV(1,2,2),NX,NX, 1,NY,NX,NY)
    CALL EDG3D(XYSRF,XCV(1,1,1),XCV(1,2,1), 1,NX, 1, 1,NX,NY)
    CALL EDG3D(XYSRF,XCV(1,1,2),XCV(1,2,2), 1,NX,NY,NY,NX,NY)

!     Generate intersection vectors for (i,j)

!     quick check on sign of curvature:        (pff ,  12/08/00)


    ivtx = cface(1,ifce)
    ivto = cface(2,ifce)
    vout(1) = xc(ivtx,ie)-xc(ivto,ie)
    vout(2) = yc(ivtx,ie)-yc(ivto,ie)
    vout(3) = zc(ivtx,ie)-zc(ivto,ie)

    vsph(1) = xc(ivtx,ie)-xctr
    vsph(2) = yc(ivtx,ie)-yctr
    vsph(3) = zc(ivtx,ie)-zctr
    ifconcv = .TRUE. 
    sign    = DOT(vsph,vout,3)
    if (sign > 0) ifconcv = .FALSE. 
!     write(6,*) 'THIS IS SIGN:',sign

    DO 200 J=2,NYM1
        CALL CROSS(VN1,XYSRF(1,1,J),XYSRF(1,NX,J))
        DO 200 I=2,NXM1
            CALL CROSS(VN2,XYSRF(1,I,1),XYSRF(1,I,NY))
            if (ifconcv) then
            !           IF (IFACE.EQ.1.OR.IFACE.EQ.4.OR.IFACE.EQ.5) THEN
                CALL CROSS(XYSRF(1,I,J),VN2,VN1)
            ELSE
                CALL CROSS(XYSRF(1,I,J),VN1,VN2)
            ENDIF
    200 END DO

!     Normalize all vectors to the unit sphere.

    DO 300 I=1,NXY
        CALL NORM3D(XYSRF(1,I,1))
    300 END DO

!     Scale by actual radius

    CALL CMULT(XYSRF,RADIUS,NXY3)

!     Add back the sphere center offset

    DO 400 I=1,NXY
        XYSRF(1,I,1)=XYSRF(1,I,1)+XCTR
        XYSRF(2,I,1)=XYSRF(2,I,1)+YCTR
        XYSRF(3,I,1)=XYSRF(3,I,1)+ZCTR
    400 END DO


!     Transpose data, if necessary

    IF (IFACE == 1 .OR. IFACE == 4 .OR. IFACE == 5) THEN
        DO 500 J=1  ,NY
            DO 500 I=J+1,NX
                TMP=XYSRF(1,I,J)
                XYSRF(1,I,J)=XYSRF(1,J,I)
                XYSRF(1,J,I)=TMP
                TMP=XYSRF(2,I,J)
                XYSRF(2,I,J)=XYSRF(2,J,I)
                XYSRF(2,J,I)=TMP
                TMP=XYSRF(3,I,J)
                XYSRF(3,I,J)=XYSRF(3,J,I)
                XYSRF(3,J,I)=TMP
        500 END DO
    ENDIF

!     Compute surface deflection and perturbation due to face IFACE

    CALL DSSET(NX,NY,NZ)
    JS1    = SKPDAT(1,IFACE)
    JF1    = SKPDAT(2,IFACE)
    JSKIP1 = SKPDAT(3,IFACE)
    JS2    = SKPDAT(4,IFACE)
    JF2    = SKPDAT(5,IFACE)
    JSKIP2 = SKPDAT(6,IFACE)

    IOPP(1) = NX-1
    IOPP(2) = NX*(NY-1)
    IOPP(3) = NX*NY*(NZ-1)
    NXX(1)  = NX
    NXX(2)  = NY
    NXX(3)  = NZ
    IDIR    = 2*MOD(IFACE,2) - 1
    IFC2    = (IFACE+1)/2
    DELT    = 0.0
    I=0
    DO 700 J2=JS2,JF2,JSKIP2
        DO 700 J1=JS1,JF1,JSKIP1
            I=I+1
            JOPP = J1 + IOPP(IFC2)*IDIR
            X2(1) = XML(J1,J2,1,IE)
            X2(2) = YML(J1,J2,1,IE)
            X2(3) = ZML(J1,J2,1,IE)
        
            DX(1) = XYSRF(1,I,1)-X2(1)
            DX(2) = XYSRF(2,I,1)-X2(2)
            DX(3) = XYSRF(3,I,1)-X2(3)
        
            NXS = NXX(IFC2)
            JOFF = (J1-JOPP)/(NXS-1)
            DO 600 IX = 2,NXS
                J = JOPP + JOFF*(IX-1)
                ZETA = 0.5*(ZGML(IX,IFC2) + 1.0)
                XML(J,J2,1,IE) = XML(J,J2,1,IE)+DX(1)*ZETA
                YML(J,J2,1,IE) = YML(J,J2,1,IE)+DX(2)*ZETA
                ZML(J,J2,1,IE) = ZML(J,J2,1,IE)+DX(3)*ZETA
            600 END DO
    700 END DO

    return
    end subroutine sphsrf
!-----------------------------------------------------------------------
    subroutine edg3d(xysrf,x1,x2,i1,i2,j1,j2,nx,ny)

!     Generate XYZ vector along an edge of a surface.

    use size_m
    COMMON /CTMP1/ H(LX1,3,2),XCRVED(LX1),YCRVED(LY1),ZCRVED(LZ1) &
    , ZGML(LX1,3),WORK(3,LX1,LZ1)

    DIMENSION XYSRF(3,NX,NY)
    DIMENSION X1(3),X2(3)
    REAL :: U1(3),U2(3),VN(3),B(3)

!     Normalize incoming vectors

    CALL COPY (U1,X1,3)
    CALL COPY (U2,X2,3)
    CALL NORM3D (U1)
    CALL NORM3D (U2)

!     Find normal to the plane and tangent to the curve.

    CALL CROSS(VN,X1,X2)
    CALL CROSS( B,VN,X1)
    CALL NORM3D (VN)
    CALL NORM3D (B)

    CTHETA = DOT(U1,U2,3)
    THETA  = ACOS(CTHETA)

    IJ = 0
    DO 200 J=J1,J2
        DO 200 I=I1,I2
            IJ = IJ + 1
            THETAP = 0.5*THETA*(ZGML(IJ,1)+1.0)
            CTP = COS(THETAP)
            STP = SIN(THETAP)
            DO 200 IV = 1,3
                XYSRF(IV,I,J) = CTP*U1(IV) + STP*B(IV)
    200 END DO
    return
    end subroutine edg3d
    REAL FUNCTION DOT(V1,V2,N)

!     Compute Cartesian vector dot product.

    DIMENSION V1(N),V2(N)

    SUM = 0
    DO 100 I=1,N
        SUM = SUM + V1(I)*V2(I)
    100 END DO
    DOT = SUM
    return
    END FUNCTION DOT
!-----------------------------------------------------------------------
    subroutine cross(v1,v2,v3)

!     Compute Cartesian vector dot product.

    DIMENSION V1(3),V2(3),V3(3)

    V1(1) = V2(2)*V3(3) - V2(3)*V3(2)
    V1(2) = V2(3)*V3(1) - V2(1)*V3(3)
    V1(3) = V2(1)*V3(2) - V2(2)*V3(1)

    return
    end subroutine cross
!-----------------------------------------------------------------------
    subroutine norm3d(v1)

!     Compute Cartesian vector dot product.

    DIMENSION V1(3)

    VLNGTH = DOT(V1,V1,3)
    VLNGTH = SQRT(VLNGTH)
    if (vlngth > 0) then
        V1(1) = V1(1) / VLNGTH
        V1(2) = V1(2) / VLNGTH
        V1(3) = V1(3) / VLNGTH
    endif

    return
    end subroutine norm3d
!-----------------------------------------------------------------------
    subroutine crn3d(xcv,xc,yc,zc,curve,iface)
    use size_m
    use topol
    DIMENSION XCV(3,2,2),XC(8),YC(8),ZC(8),CURVE(4)
    DIMENSION INDVTX(4,6)
    SAVE      INDVTX
    DATA      INDVTX  / 1,5,3,7 , 2,4,6,8 , 1,2,5,6 &
    , 3,7,4,8 , 1,3,2,4 , 5,6,7,8 /

    EPS    = 1.0E-4
    XCTR   = CURVE(1)
    YCTR   = CURVE(2)
    ZCTR   = CURVE(3)
    RADIUS = CURVE(4)

    DO 10 I=1,4
        J=INDVTX(I,IFACE)
        K=INDX(J)
        XCV(1,I,1)=XC(K)-XCTR
        XCV(2,I,1)=YC(K)-YCTR
        XCV(3,I,1)=ZC(K)-ZCTR
    10 END DO

!     Check to ensure that these points are indeed on the sphere.

    IF (RADIUS <= 0.0) THEN
        write(6,20) NID,XCTR,YCTR,ZCTR,IFACE
        20 FORMAT(I5,'ERROR: Sphere of radius zero requested.' &
        ,/,5X,'EXITING in CRN3D',3E12.4,I3)
        call exitt
    ELSE
        DO 40 I=1,4
            RADT=XCV(1,I,1)**2+XCV(2,I,1)**2+XCV(3,I,1)**2
            RADT=SQRT(RADT)
            TEST=ABS(RADT-RADIUS)/RADIUS
            IF (TEST > EPS) THEN
                write(6,30) NID &
                ,RADT,RADIUS,XCV(1,I,1),XCV(2,I,1),XCV(3,I,1)
                30 FORMAT(I5,'ERROR: Element vertex not on requested sphere.' &
                ,/,5X,'EXITING in CRN3D',5E12.4)
                call exitt
            ENDIF
        40 END DO
    ENDIF

    return
    end subroutine crn3d
!-----------------------------------------------------------------------
    subroutine gensrf(XML,YML,ZML,IFCE,IE,MX,MY,MZ,zgml)

!     9 Mar 1994

!     Program to generate surface deformations for NEKTON
!     input.  Paul F. Fischer

!     include 'basics.inc'
    use size_m
    use input
    use topol
    use wz_m

    DIMENSION XML(MX,MY,MZ,1),YML(MX,MY,MZ,1),ZML(MX,MY,MZ,1) &
    ,ZGML(MX,3)

    real :: IOPP(3),MXX(3),X0(3),DX(3)


!     Algorithm:  .Project original point onto surface S
!                 .Apply Gordon Hall to vector of points between x_s and
!                  opposite face


    CALL DSSET(MX,MY,MZ)

    IFACE  = EFACE1(IFCE)

!     Beware!!  SKPDAT different from preprocessor/postprocessor!

    JS1    = SKPDAT(1,IFACE)
    JF1    = SKPDAT(2,IFACE)
    JSKIP1 = SKPDAT(3,IFACE)
    JS2    = SKPDAT(4,IFACE)
    JF2    = SKPDAT(5,IFACE)
    JSKIP2 = SKPDAT(6,IFACE)

    IOPP(1) = MX-1
    IOPP(2) = MX*(MY-1)
    IOPP(3) = MX*MY*(MZ-1)
    MXX(1)  = MX
    MXX(2)  = MY
    MXX(3)  = MZ
    IDIR    = 2*MOD(IFACE,2) - 1
    IFC2    = (IFACE+1)/2
    I=0

!     Find a characteristic length scale for initializing secant method

    x0(1) = xml(js1,js2,1,ie)
    x0(2) = yml(js1,js2,1,ie)
    x0(3) = zml(js1,js2,1,ie)
    rmin  = 1.0e16



    DO 100 J2=JS2,JF2,JSKIP2
        DO 100 J1=JS1,JF1,JSKIP1
            if (j1 /= js1 .OR. j2 /= js2) then
                r2 = (x0(1) - xml(j1,j2,1,ie))**2 &
                + (x0(2) - yml(j1,j2,1,ie))**2 &
                + (x0(3) - zml(j1,j2,1,ie))**2
                rmin = min(r2,rmin)
            endif
    100 END DO
    dxc = 0.05*sqrt(rmin)

!     Project each point on this surface onto curved surface

    DO 300 J2=JS2,JF2,JSKIP2
        DO 300 J1=JS1,JF1,JSKIP1
            I=I+1
            JOPP = J1 + IOPP(IFC2)*IDIR
            X0(1) = XML(J1,J2,1,IE)
            X0(2) = YML(J1,J2,1,IE)
            X0(3) = ZML(J1,J2,1,IE)
        
            call prjects(x0,dxc,curve(1,ifce,ie),ccurve(ifce,ie))
            DX(1) = X0(1)-xml(j1,j2,1,ie)
            DX(2) = X0(2)-yml(j1,j2,1,ie)
            DX(3) = X0(3)-zml(j1,j2,1,ie)
            MXS = MXX(IFC2)
            JOFF = (J1-JOPP)/(MXS-1)
            DO 200 IX = 2,MXS
                J = JOPP + JOFF*(IX-1)
                ZETA = 0.5*(ZGML(IX,1) + 1.0)
                XML(J,J2,1,IE) = XML(J,J2,1,IE)+DX(1)*ZETA
                YML(J,J2,1,IE) = YML(J,J2,1,IE)+DX(2)*ZETA
                ZML(J,J2,1,IE) = ZML(J,J2,1,IE)+DX(3)*ZETA
            200 END DO
    300 END DO

    return
    end subroutine gensrf
!-----------------------------------------------------------------------
    subroutine prjects(x0,dxc,c,cc)

!     Project the point x0 onto surface described by characteristics
!     given in the array c and cc.

!     dxc - characteristic length scale used to estimate gradient.

    real :: x0(3)
    real :: c(5)
    character(1) :: cc
    real :: x1(3)
    logical :: if3d

    if3d = .TRUE. 
    if (dxc <= 0.0) then
        write(6,*) 'invalid dxc',dxc,x0
        write(6,*) 'Abandoning prjects'
        return
    endif

    call copy(x1,x0,3)
    R0 = ressrf(x0,c,cc)
    if (r0 == 0) return

!     Must at least use ctr differencing to capture symmetry!

    x1(1) = x0(1) - dxc
    R1 = ressrf(x1,c,cc)
    x1(1) = x0(1) + dxc
    R2 = ressrf(x1,c,cc)
    x1(1) = x0(1)
    Rx = 0.5*(R2-R1)/dxc

    x1(2) = x0(2) - dxc
    R1 = ressrf(x1,c,cc)/dxc
    x1(2) = x0(2) + dxc
    R2 = ressrf(x1,c,cc)/dxc
    x1(2) = x0(2)
    Ry = 0.5*(R2-R1)/dxc

    if (if3d) then
        x1(3) = x0(3) - dxc
        R1 = ressrf(x1,c,cc)/dxc
        x1(3) = x0(3) + dxc
        R2 = ressrf(x1,c,cc)/dxc
        Rz = 0.5*(R2-R1)/dxc
    endif
    Rnorm2 = Rx**2 + Ry**2 + Rz**2
    alpha  = - R0/Rnorm2

!     Apply secant method:  Use an initial segment twice expected length

    x1(1) = x0(1) + 2.0*Rx * alpha
    x1(2) = x0(2) + 2.0*Ry * alpha
    x1(3) = x0(3) + 2.0*Rz * alpha
    call srfind(x1,x0,c,cc)

!     write(6,6) cc,c(2),c(3),x0,x1
!   6 format(1x,a1,1x,2f5.2,3f9.4,3x,3f9.4)

    call copy(x0,x1,3)

    return
    end subroutine prjects
!-----------------------------------------------------------------------
    subroutine srfind(x1,x0,c,cc)
    real :: x1(3),x0(3)
    real :: c(5)
    character(1) :: cc

!     Find point on line segment that intersects the ellipsoid
!     specified by:
!                       (x/a)**2 + (y/b)**2 + (z/b)**2 = 1


!     Algorithm:  4 rounds of secant  x_k+1 = x_k - f/f'

    a0 = 0.0
    a1 = 1.0
    r0 = ressrf(x0,c,cc)
    dx = x1(1) - x0(1)
    dy = x1(2) - x0(2)
    dz = x1(3) - x0(3)
!     write(6,*) 'dxyz',dx,dy,dz
!     write(6,*) 'cc  ',x0,cc,c(2),c(3)
    do 10 i=1,9
        r1 = ressrf(x1,c,cc)
        if (r1 /= r0) then
            da = r1*(a1-a0)/(r1-r0)
            r0 = r1
            a0 = a1
            a1 = a1 - da
        endif
        x1(1) = x0(1) + a1*dx
        x1(2) = x0(2) + a1*dy
        x1(3) = x0(3) + a1*dz
    10 END DO
!     write(6,*) ' r1',r1,r0,a1
    return
    end subroutine srfind
!-----------------------------------------------------------------------
    function ressrf(x,c,cc)
    real :: x(3)
    real :: c(5)
    character(1) :: cc

    ressrf = 0.0
    if (cc == 'e') then
        a = c(2)
        b = c(3)
        ressrf = 1.0 - (x(1)/a)**2 - (x(2)/b)**2 - (x(3)/b)**2
        return
    endif

    return
    end function ressrf
!-----------------------------------------------------------------------
    subroutine linquad(xl,yl,zl,nxl,nyl,nzl)

    use size_m
    use geom
    use input
    use parallel
    use topol
    use wz_m

    real :: xl(nxl*nyl*nzl,1),yl(nxl*nyl*nzl,1),zl(nxl*nyl*nzl,1)

    integer :: e
    logical :: ifmid

    nedge = 4 + 8*(ndim-2)

    do e=1,nelt ! Loop over all elements

        ifmid = .FALSE. 
        do k=1,nedge
            if (ccurve(k,e) == 'm') ifmid = .TRUE. 
        enddo

        if (lx1 == 2) ifmid = .FALSE. 
        if (ifmid) then
          write(*,*) "Oops: ifmid"
!max            call xyzquad(xl(1,e),yl(1,e),zl(1,e),nxl,nyl,nzl,e)
        else
            call xyzlin (xl(1,e),yl(1,e),zl(1,e),nxl,nyl,nzl,e,ifaxis)
        endif
    enddo

    return
    end subroutine linquad
!-----------------------------------------------------------------------
!> \brief Generate bi- or trilinear mesh
subroutine xyzlin(xl,yl,zl,nxl,nyl,nzl,e,ifaxl)
  use kinds, only : DP
  use size_m
  use input
  implicit none

  integer :: nxl, nyl, nzl, e
  real(DP) :: xl(nxl,nyl,nzl),yl(nxl,nyl,nzl),zl(nxl,nyl,nzl)
  logical :: ifaxl ! local ifaxis specification

! Preprocessor Corner notation:      Symmetric Corner notation:

!         4+-----+3    ^ s                    3+-----+4    ^ s
!         /     /|     |                      /     /|     |
!        /     / |     |                     /     / |     |
!      8+-----+7 +2    +----> r            7+-----+8 +2    +----> r
!       |     | /     /                     |     | /     /
!       |     |/     /                      |     |/     /
!      5+-----+6    t                      5+-----+6    t

  integer, save :: indx(8) = (/ 1,2,4,3,5,6,8,7 /)

  integer, parameter :: ldw=4*lx1*ly1*lz1
  real(DP) :: xcb, ycb, zcb, w
  common /ctmp0/ xcb(2,2,2),ycb(2,2,2),zcb(2,2,2),w(ldw)

!  real(DP) :: zgml, jx,jy,jz,jxt,jyt,jzt, zlin
  real(DP) :: zgml(lx1,3),jx (lx1*2),jy (lx1*2),jz (lx1*2)
  real(DP) :: jxt(lx1*2),jyt(lx1*2),jzt(lx1*2),zlin(2)

  integer :: i, k, ix, ndim2

  call setzgml (zgml,e,nxl,nyl,nzl,ifaxl)

  zlin(1) = -1
  zlin(2) =  1

  k = 1
  do i=1,nxl
      call fd_weights_full(zgml(i,1),zlin,1,0,jxt(k))
      call fd_weights_full(zgml(i,2),zlin,1,0,jyt(k))
      call fd_weights_full(zgml(i,3),zlin,1,0,jzt(k))
      k=k+2
  enddo
  call transpose(jx,nxl,jxt,2)

  ndim2 = 2**ndim
  do ix=1,ndim2          ! Convert prex notation to lexicographical
      i=indx(ix)
      xcb(ix,1,1)=xc(i,e)
      ycb(ix,1,1)=yc(i,e)
      zcb(ix,1,1)=zc(i,e)
  enddo

!   Map R-S-T space into physical X-Y-Z space.

! NOTE:  Assumes nxl=nyl=nzl !

  call tensr3(xl,nxl,xcb,2,jx,jyt,jzt,w)
  call tensr3(yl,nxl,ycb,2,jx,jyt,jzt,w)
  call tensr3(zl,nxl,zcb,2,jx,jyt,jzt,w)

  return
end subroutine xyzlin
!-----------------------------------------------------------------------
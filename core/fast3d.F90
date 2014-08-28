!-----------------------------------------------------------------------
    subroutine gen_fast_spacing(x,y,z)

!     Generate fast diagonalization matrices for each element

    use size_m
    use input
    use parallel
    use soln
    use wz_m

    parameter(lxx=lx1*lx1)

    common /ctmpf/  lr(2*lx1+4),ls(2*lx1+4),lt(2*lx1+4) &
    , llr(lelt),lls(lelt),llt(lelt) &
    , lmr(lelt),lms(lelt),lmt(lelt) &
    , lrr(lelt),lrs(lelt),lrt(lelt)
    real :: lr ,ls ,lt
    real :: llr,lls,llt
    real :: lmr,lms,lmt
    real :: lrr,lrs,lrt

    integer :: lbr,rbr,lbs,rbs,lbt,rbt,e

    real :: x(nx1,ny1,nz1,nelv)
    real :: y(nx1,ny1,nz1,nelv)
    real :: z(nx1,ny1,nz1,nelv)
    real :: axwt(lx2)

    ierr = 0

    if (param(44) == 1) then
    !                                    __ __ __
    !        Now, for each element, compute lr,ls,lt between specified planes
    
        n1 = nx2
        n2 = nx2+1
        nz0 = 1
        nzn = 1
        if (if3d) then
            nz0= 0
            nzn=n2
        endif
        eps = 1.e-7
        if (wdsize == 8)  eps = 1.e-14
    
    !        Find mean spacing between "left-most" planes
        call plane_space2(llr,lls,llt, 0,wxm2,x,y,z,n1,n2,nz0,nzn)
    
    !        Find mean spacing between "middle" planes
        call plane_space (lmr,lms,lmt, 1,n1,wxm2,x,y,z,n1,n2,nz0,nzn)
    
    !        Find mean spacing between "right-most" planes
        call plane_space2(lrr,lrs,lrt,n2,wxm2,x,y,z,n1,n2,nz0,nzn)
    
    else
        call load_semhat_weighted    !   Fills the SEMHAT arrays
    endif

    return
    end subroutine gen_fast_spacing
!-----------------------------------------------------------------------
    subroutine plane_space_std(lr,ls,lt,i1,i2,w,x,y,z,nx,nxn,nz0,nzn)

!     This routine now replaced by "plane_space()"

!     Here, spacing is based on arithmetic mean.
!     New verision uses harmonic mean.  pff 2/10/07

    use size_m
    use input

    real :: w(1),lr(1),ls(1),lt(1)
    real :: x(0:nxn,0:nxn,nz0:nzn,1)
    real :: y(0:nxn,0:nxn,nz0:nzn,1)
    real :: z(0:nxn,0:nxn,nz0:nzn,1)
    real :: lr2,ls2,lt2
!                                    __ __ __
!     Now, for each element, compute lr,ls,lt between specified planes

    ny = nx
    nz = nx
    j1 = i1
    k1 = i1
    j2 = i2
    k2 = i2

    do ie=1,nelv
    
        if (if3d) then
            lr2  = 0.
            wsum = 0.
            do k=1,nz
                do j=1,ny
                    weight = w(j)*w(k)
                    lr2  = lr2  + ( (x(i2,j,k,ie)-x(i1,j,k,ie))**2 &
                    +   (y(i2,j,k,ie)-y(i1,j,k,ie))**2 &
                    +   (z(i2,j,k,ie)-z(i1,j,k,ie))**2 ) &
                    *   weight
                    wsum = wsum + weight
                enddo
            enddo
            lr2     = lr2/wsum
            lr(ie)  = sqrt(lr2)
        
            ls2 = 0.
            wsum = 0.
            do k=1,nz
                do i=1,nx
                    weight = w(i)*w(k)
                    ls2  = ls2  + ( (x(i,j2,k,ie)-x(i,j1,k,ie))**2 &
                    +   (y(i,j2,k,ie)-y(i,j1,k,ie))**2 &
                    +   (z(i,j2,k,ie)-z(i,j1,k,ie))**2 ) &
                    *   weight
                    wsum = wsum + weight
                enddo
            enddo
            ls2     = ls2/wsum
            ls(ie)  = sqrt(ls2)
        
            lt2 = 0.
            wsum = 0.
            do j=1,ny
                do i=1,nx
                    weight = w(i)*w(j)
                    lt2  = lt2  + ( (x(i,j,k2,ie)-x(i,j,k1,ie))**2 &
                    +   (y(i,j,k2,ie)-y(i,j,k1,ie))**2 &
                    +   (z(i,j,k2,ie)-z(i,j,k1,ie))**2 ) &
                    *   weight
                    wsum = wsum + weight
                enddo
            enddo
            lt2     = lt2/wsum
            lt(ie)  = sqrt(lt2)
        
        else
            lr2 = 0.
            wsum = 0.
            do j=1,ny
                weight = w(j)
                lr2  = lr2  + ( (x(i2,j,1,ie)-x(i1,j,1,ie))**2 &
                +   (y(i2,j,1,ie)-y(i1,j,1,ie))**2 ) &
                *   weight
                wsum = wsum + weight
            enddo
            lr2     = lr2/wsum
            lr(ie)  = sqrt(lr2)
        
            ls2 = 0.
            wsum = 0.
            do i=1,nx
                weight = w(i)
                ls2  = ls2  + ( (x(i,j2,1,ie)-x(i,j1,1,ie))**2 &
                +   (y(i,j2,1,ie)-y(i,j1,1,ie))**2 ) &
                *   weight
                wsum = wsum + weight
            enddo
            ls2     = ls2/wsum
            ls(ie)  = sqrt(ls2)
        !           write(6,*) 'lrls',ie,lr(ie),ls(ie)
        endif
    enddo
    return
    end subroutine plane_space_std
!-----------------------------------------------------------------------
    subroutine plane_space(lr,ls,lt,i1,i2,w,x,y,z,nx,nxn,nz0,nzn)

!     Here, spacing is based on harmonic mean.  pff 2/10/07


    use size_m
    use input

    real :: w(1),lr(1),ls(1),lt(1)
    real :: x(0:nxn,0:nxn,nz0:nzn,1)
    real :: y(0:nxn,0:nxn,nz0:nzn,1)
    real :: z(0:nxn,0:nxn,nz0:nzn,1)
    real :: lr2,ls2,lt2
!                                    __ __ __
!     Now, for each element, compute lr,ls,lt between specified planes

    ny = nx
    nz = nx
    j1 = i1
    k1 = i1
    j2 = i2
    k2 = i2

    do ie=1,nelv
    
        if (if3d) then
            lr2  = 0.
            wsum = 0.
            do k=1,nz
                do j=1,ny
                    weight = w(j)*w(k)
                !              lr2  = lr2  + ( (x(i2,j,k,ie)-x(i1,j,k,ie))**2
                !    $                     +   (y(i2,j,k,ie)-y(i1,j,k,ie))**2
                !    $                     +   (z(i2,j,k,ie)-z(i1,j,k,ie))**2 )
                !    $                     *   weight
                    lr2  = lr2  +   weight / &
                    ( (x(i2,j,k,ie)-x(i1,j,k,ie))**2 &
                    +   (y(i2,j,k,ie)-y(i1,j,k,ie))**2 &
                    +   (z(i2,j,k,ie)-z(i1,j,k,ie))**2 )
                    wsum = wsum + weight
                enddo
            enddo
            lr2     = lr2/wsum
            lr(ie)  = 1./sqrt(lr2)
        
            ls2 = 0.
            wsum = 0.
            do k=1,nz
                do i=1,nx
                    weight = w(i)*w(k)
                !              ls2  = ls2  + ( (x(i,j2,k,ie)-x(i,j1,k,ie))**2
                !    $                     +   (y(i,j2,k,ie)-y(i,j1,k,ie))**2
                !    $                     +   (z(i,j2,k,ie)-z(i,j1,k,ie))**2 )
                !    $                     *   weight
                    ls2  = ls2  +   weight / &
                    ( (x(i,j2,k,ie)-x(i,j1,k,ie))**2 &
                    +   (y(i,j2,k,ie)-y(i,j1,k,ie))**2 &
                    +   (z(i,j2,k,ie)-z(i,j1,k,ie))**2 )
                    wsum = wsum + weight
                enddo
            enddo
            ls2     = ls2/wsum
            ls(ie)  = 1./sqrt(ls2)
        
            lt2 = 0.
            wsum = 0.
            do j=1,ny
                do i=1,nx
                    weight = w(i)*w(j)
                !              lt2  = lt2  + ( (x(i,j,k2,ie)-x(i,j,k1,ie))**2
                !    $                     +   (y(i,j,k2,ie)-y(i,j,k1,ie))**2
                !    $                     +   (z(i,j,k2,ie)-z(i,j,k1,ie))**2 )
                !    $                     *   weight
                    lt2  = lt2  +   weight / &
                    ( (x(i,j,k2,ie)-x(i,j,k1,ie))**2 &
                    +   (y(i,j,k2,ie)-y(i,j,k1,ie))**2 &
                    +   (z(i,j,k2,ie)-z(i,j,k1,ie))**2 )
                    wsum = wsum + weight
                enddo
            enddo
            lt2     = lt2/wsum
            lt(ie)  = 1./sqrt(lt2)
        
        else              ! 2D
            lr2 = 0.
            wsum = 0.
            do j=1,ny
                weight = w(j)
            !              lr2  = lr2  + ( (x(i2,j,1,ie)-x(i1,j,1,ie))**2
            !    $                     +   (y(i2,j,1,ie)-y(i1,j,1,ie))**2 )
            !    $                     *   weight
                lr2  = lr2  + weight / &
                ( (x(i2,j,1,ie)-x(i1,j,1,ie))**2 &
                + (y(i2,j,1,ie)-y(i1,j,1,ie))**2 )
                wsum = wsum + weight
            enddo
            lr2     = lr2/wsum
            lr(ie)  = 1./sqrt(lr2)
        
            ls2 = 0.
            wsum = 0.
            do i=1,nx
                weight = w(i)
            !              ls2  = ls2  + ( (x(i,j2,1,ie)-x(i,j1,1,ie))**2
            !    $                     +   (y(i,j2,1,ie)-y(i,j1,1,ie))**2 )
            !    $                     *   weight
                ls2  = ls2  + weight / &
                ( (x(i,j2,1,ie)-x(i,j1,1,ie))**2 &
                +   (y(i,j2,1,ie)-y(i,j1,1,ie))**2 )
                wsum = wsum + weight
            enddo
            ls2     = ls2/wsum
            ls(ie)  = 1./sqrt(ls2)
        !           write(6,*) 'lrls',ie,lr(ie),ls(ie)
        endif
    enddo
    return
    end subroutine plane_space
!-----------------------------------------------------------------------
    subroutine plane_space2(lr,ls,lt,i1,w,x,y,z,nx,nxn,nz0,nzn)

!     Here, the local spacing is already given in the surface term.
!     This addition made to simplify the periodic bdry treatment.


    use size_m
    use input

    real :: w(1),lr(1),ls(1),lt(1)
    real :: x(0:nxn,0:nxn,nz0:nzn,1)
    real :: y(0:nxn,0:nxn,nz0:nzn,1)
    real :: z(0:nxn,0:nxn,nz0:nzn,1)
    real :: lr2,ls2,lt2
!                                    __ __ __
!     Now, for each element, compute lr,ls,lt between specified planes

    ny = nx
    nz = nx
    j1 = i1
    k1 = i1

    do ie=1,nelv
    
        if (if3d) then
            lr2  = 0.
            wsum = 0.
            do k=1,nz
                do j=1,ny
                    weight = w(j)*w(k)
                    lr2  = lr2  + ( (x(i1,j,k,ie))**2 &
                    +   (y(i1,j,k,ie))**2 &
                    +   (z(i1,j,k,ie))**2 ) &
                    *   weight
                    wsum = wsum + weight
                enddo
            enddo
            lr2     = lr2/wsum
            lr(ie)  = sqrt(lr2)
        
            ls2 = 0.
            wsum = 0.
            do k=1,nz
                do i=1,nx
                    weight = w(i)*w(k)
                    ls2  = ls2  + ( (x(i,j1,k,ie))**2 &
                    +   (y(i,j1,k,ie))**2 &
                    +   (z(i,j1,k,ie))**2 ) &
                    *   weight
                    wsum = wsum + weight
                enddo
            enddo
            ls2     = ls2/wsum
            ls(ie)  = sqrt(ls2)
        
            lt2 = 0.
            wsum = 0.
            do j=1,ny
                do i=1,nx
                    weight = w(i)*w(j)
                    lt2  = lt2  + ( (x(i,j,k1,ie))**2 &
                    +   (y(i,j,k1,ie))**2 &
                    +   (z(i,j,k1,ie))**2 ) &
                    *   weight
                    wsum = wsum + weight
                enddo
            enddo
            lt2     = lt2/wsum
            lt(ie)  = sqrt(lt2)
        !           write(6,1) 'lrlslt',ie,lr(ie),ls(ie),lt(ie)
            1 format(a6,i5,1p3e12.4)
        
        else
            lr2 = 0.
            wsum = 0.
            do j=1,ny
                weight = w(j)
                lr2  = lr2  + ( (x(i1,j,1,ie))**2 &
                +   (y(i1,j,1,ie))**2 ) &
                *   weight
                wsum = wsum + weight
            enddo
            lr2     = lr2/wsum
            lr(ie)  = sqrt(lr2)
        
            ls2 = 0.
            wsum = 0.
            do i=1,nx
                weight = w(i)
                ls2  = ls2  + ( (x(i,j1,1,ie))**2 &
                +   (y(i,j1,1,ie))**2 ) &
                *   weight
                wsum = wsum + weight
            enddo
            ls2     = ls2/wsum
            ls(ie)  = sqrt(ls2)
        !           write(6,*) 'lrls',ie,lr(ie),ls(ie),lt(ie)
        endif
    enddo
    return
    end subroutine plane_space2
!-----------------------------------------------------------------------
    subroutine get_fast_bc(lbr,rbr,lbs,rbs,lbt,rbt,e,bsym,ierr)

    use size_m
    use input
    use parallel
    use topol
    use tstep

    integer ::                lbr,rbr,lbs,rbs,lbt,rbt,e,bsym
    integer :: fbc(6)

!     ibc = 0  <==>  Dirichlet
!     ibc = 1  <==>  Dirichlet, outflow (no extension)
!     ibc = 2  <==>  Neumann,


    do iface=1,2*ndim
        ied = eface(iface)
        ibc = -1

!max        if (ifmhd) call mhd_bc_dn(ibc,iface,e) ! can be overwritten by 'mvn'

        if (cbc(ied,e,ifield) == '   ') ibc = 0
        if (cbc(ied,e,ifield) == 'E  ') ibc = 0
        if (cbc(ied,e,ifield) == 'msi') ibc = 0
        if (cbc(ied,e,ifield) == 'MSI') ibc = 0
        if (cbc(ied,e,ifield) == 'P  ') ibc = 0
        if (cbc(ied,e,ifield) == 'p  ') ibc = 0
        if (cbc(ied,e,ifield) == 'O  ') ibc = 1
        if (cbc(ied,e,ifield) == 'ON ') ibc = 1
        if (cbc(ied,e,ifield) == 'o  ') ibc = 1
        if (cbc(ied,e,ifield) == 'on ') ibc = 1
        if (cbc(ied,e,ifield) == 'MS ') ibc = 1
        if (cbc(ied,e,ifield) == 'ms ') ibc = 1
        if (cbc(ied,e,ifield) == 'MM ') ibc = 1
        if (cbc(ied,e,ifield) == 'mm ') ibc = 1
        if (cbc(ied,e,ifield) == 'mv ') ibc = 2
        if (cbc(ied,e,ifield) == 'mvn') ibc = 2
        if (cbc(ied,e,ifield) == 'v  ') ibc = 2
        if (cbc(ied,e,ifield) == 'V  ') ibc = 2
        if (cbc(ied,e,ifield) == 'W  ') ibc = 2
        if (cbc(ied,e,ifield) == 'SYM') ibc = bsym
        if (cbc(ied,e,ifield) == 'SL ') ibc = 2
        if (cbc(ied,e,ifield) == 'sl ') ibc = 2
        if (cbc(ied,e,ifield) == 'SHL') ibc = 2
        if (cbc(ied,e,ifield) == 'shl') ibc = 2
        if (cbc(ied,e,ifield) == 'A  ') ibc = 2
        if (cbc(ied,e,ifield) == 'S  ') ibc = 2
        if (cbc(ied,e,ifield) == 's  ') ibc = 2
        if (cbc(ied,e,ifield) == 'J  ') ibc = 0
        if (cbc(ied,e,ifield) == 'SP ') ibc = 0

        fbc(iface) = ibc

        if (ierr == -1) write(6,1) ibc,ied,e,ifield,cbc(ied,e,ifield)
        1 format(2i3,i8,i3,2x,a3,'  get_fast_bc_error')

    enddo

    if (ierr == -1) call exitti('Error A get_fast_bc$',e)

    lbr = fbc(1)
    rbr = fbc(2)
    lbs = fbc(3)
    rbs = fbc(4)
    lbt = fbc(5)
    rbt = fbc(6)

    ierr = 0
    if (ibc < 0) ierr = lglel(e)

!     write(6,6) e,lbr,rbr,lbs,rbs,(cbc(k,e,ifield),k=1,4)
!   6 format(i5,2x,4i3,3x,4(1x,a3),'  get_fast_bc')

    return
    end subroutine get_fast_bc
!-----------------------------------------------------------------------
    subroutine outv(x,n,name3)
    character(3) :: name3
    real :: x(1)

    nn = min (n,10)
    write(6,6) name3,(x(i),i=1,nn)
    6 format(a3,10f12.6)

    return
    end subroutine outv
!-----------------------------------------------------------------------
    subroutine outmat(a,m,n,name6,ie)
    real :: a(m,n)
    character(6) :: name6

    write(6,*)
    write(6,*) ie,' matrix: ',name6,m,n
    n12 = min(n,12)
    do i=1,m
        write(6,6) ie,name6,(a(i,j),j=1,n12)
    enddo
    6 format(i3,1x,a6,12f9.5)
    write(6,*)
    return
    end subroutine outmat
!-----------------------------------------------------------------------
    subroutine load_semhat_weighted    !   Fills the SEMHAT arrays

!     Note that this routine performs the following matrix multiplies
!     after getting the matrices back from semhat:

!     dgl = bgl dgl
!     jgl = bgl jgl

    use size_m
    use semhat

    nr = nx1-1
    call generate_semhat(ah,bh,ch,dh,zh,dph,jph,bgl,zgl,dgl,jgl,nr,wh)
    call do_semhat_weight(jgl,dgl,bgl,nr)

    return
    end subroutine load_semhat_weighted
!----------------------------------------------------------------------
    subroutine do_semhat_weight(jgl,dgl,bgl,n)
    real :: bgl(1:n-1),jgl(1:n-1,0:n),dgl(1:n-1,0:n)

    do j=0,n
        do i=1,n-1
            jgl(i,j)=bgl(i)*jgl(i,j)
        enddo
    enddo
    do j=0,n
        do i=1,n-1
            dgl(i,j)=bgl(i)*dgl(i,j)
        enddo
    enddo
    return
    end subroutine do_semhat_weight
!-----------------------------------------------------------------------
    subroutine generate_semhat(a,b,c,d,z,dgll,jgll,bgl,zgl,dgl,jgl,n,w)

!     Generate matrices for single element, 1D operators:

!        a    = Laplacian
!        b    = diagonal mass matrix
!        c    = convection operator b*d
!        d    = derivative matrix
!        dgll = derivative matrix,    mapping from pressure nodes to velocity
!        jgll = interpolation matrix, mapping from pressure nodes to velocity
!        z    = GLL points

!        zgl  = GL points
!        bgl  = diagonal mass matrix on GL
!        dgl  = derivative matrix,    mapping from velocity nodes to pressure
!        jgl  = interpolation matrix, mapping from velocity nodes to pressure

!        n    = polynomial degree (velocity space)
!        w    = work array of size 2*n+2

!     Currently, this is set up for pressure nodes on the interior GLL pts.


    real :: a(0:n,0:n),b(0:n),c(0:n,0:n),d(0:n,0:n),z(0:n)
    real :: dgll(0:n,1:n-1),jgll(0:n,1:n-1)

    real :: bgl(1:n-1),zgl(1:n-1)
    real :: dgl(1:n-1,0:n),jgl(1:n-1,0:n)

    real :: w(0:1)

    np = n+1
    nm = n-1
    n2 = n-2

    call zwgll (z,b,np)

    do i=0,n
        call fd_weights_full(z(i),z,n,1,w)
        do j=0,n
            d(i,j) = w(j+np)                   !  Derivative matrix
        enddo
    enddo

    if (n == 1) return                       !  No interpolation for n=1

    do i=0,n
        call fd_weights_full(z(i),z(1),n2,1,w(1))
        do j=1,nm
            jgll(i,j) = w(j   )                  !  Interpolation matrix
            dgll(i,j) = w(j+nm)                  !  Derivative    matrix
        enddo
    enddo

    call rzero(a,np*np)
    do j=0,n
        do i=0,n
            do k=0,n
                a(i,j) = a(i,j) + d(k,i)*b(k)*d(k,j)
            enddo
            c(i,j) = b(i)*d(i,j)
        enddo
    enddo

    call zwgl (zgl,bgl,nm)

    do i=1,n-1
        call fd_weights_full(zgl(i),z,n,1,w)
        do j=0,n
            jgl(i,j) = w(j   )                  !  Interpolation matrix
            dgl(i,j) = w(j+np)                  !  Derivative    matrix
        enddo
    enddo

    return
    end subroutine generate_semhat
!-----------------------------------------------------------------------
    subroutine fd_weights_full(xx,x,n,m,c)

!     This routine evaluates the derivative based on all points
!     in the stencils.  It is more memory efficient than "fd_weights"

!     This set of routines comes from the appendix of
!     A Practical Guide to Pseudospectral Methods, B. Fornberg
!     Cambridge Univ. Press, 1996.   (pff)

!     Input parameters:
!       xx -- point at wich the approximations are to be accurate
!       x  -- array of x-ordinates:   x(0:n)
!       n  -- polynomial degree of interpolant (# of points := n+1)
!       m  -- highest order of derivative to be approxxmated at xi

!     Output:
!       c  -- set of coefficients c(0:n,0:m).
!             c(j,k) is to be applied at x(j) when
!             the kth derivative is approxxmated by a
!             stencil extending over x(0),x(1),...x(n).


    real :: x(0:n),c(0:n,0:m)

    c1       = 1.
    c4       = x(0) - xx

    do k=0,m
        do j=0,n
            c(j,k) = 0.
        enddo
    enddo
    c(0,0) = 1.

    do i=1,n
        mn = min(i,m)
        c2 = 1.
        c5 = c4
        c4 = x(i)-xx
        do j=0,i-1
            c3 = x(i)-x(j)
            c2 = c2*c3
            do k=mn,1,-1
                c(i,k) = c1*(k*c(i-1,k-1)-c5*c(i-1,k))/c2
            enddo
            c(i,0) = -c1*c5*c(i-1,0)/c2
            do k=mn,1,-1
                c(j,k) = (c4*c(j,k)-k*c(j,k-1))/c3
            enddo
            c(j,0) = c4*c(j,0)/c3
        enddo
        c1 = c2
    enddo
!     call outmat(c,n+1,m+1,'fdw',n)
    return
    end subroutine fd_weights_full
!-----------------------------------------------------------------------
    subroutine set_up_fast_1D_sem_op(g,b0,b1,l,r,ll,lm,lr,bh,jgl,jscl)
!            -1 T
!     G = J B  J

!     gives the inexact restriction of this matrix to
!     an element plus one node on either side

!     g - the output matrix
!     b0, b1 - the range for Bhat indices for the element
!              (enforces boundary conditions)
!     l, r - whether there is a left or right neighbor
!     ll,lm,lr - lengths of left, middle, and right elements
!     bh - hat matrix for B
!     jgl - hat matrix for J (should map vel to pressure)
!     jscl - how J scales
!            0: J = Jh
!            1: J = (L/2) Jh

!     result is inexact because:
!        neighbor's boundary condition at far end unknown
!        length of neighbor's neighbor unknown
!        (these contribs should be small for large N and
!         elements of nearly equal size)

    use size_m
    real :: g(0:lx1-1,0:lx1-1)
    real :: bh(0:lx1-1),jgl(1:lx2,0:lx1-1)
    real :: ll,lm,lr
    integer :: b0,b1
    logical :: l,r
    integer :: jscl

    real :: bl(0:lx1-1),bm(0:lx1-1),br(0:lx1-1)
    real :: gl,gm,gr,gll,glm,gmm,gmr,grr
    real :: fac
    integer :: n
    n=nx1-1


!     compute the scale factors for J
    if (jscl == 0) then
        gl=1.
        gm=1.
        gr=1.
    elseif (jscl == 1) then
        gl=0.5*ll
        gm=0.5*lm
        gr=0.5*lr
    endif
    gll = gl*gl
    glm = gl*gm
    gmm = gm*gm
    gmr = gm*gr
    grr = gr*gr

!     compute the summed inverse mass matrices for
!     the middle, left, and right elements
    do i=1,n-1
        bm(i)=2. /(lm*bh(i))
    enddo
    if (b0 == 0) then
        bm(0)=0.5*lm*bh(0)
        if(l) bm(0)=bm(0)+0.5*ll*bh(n)
        bm(0)=1. /bm(0)
    endif
    if (b1 == n) then
        bm(n)=0.5*lm*bh(n)
        if(r) bm(n)=bm(n)+0.5*lr*bh(0)
        bm(n)=1. /bm(n)
    endif
!     note that in computing bl for the left element,
!     bl(0) is missing the contribution from its left neighbor
    if (l) then
        do i=0,n-1
            bl(i)=2. /(ll*bh(i))
        enddo
        bl(n)=bm(0)
    endif
!     note that in computing br for the right element,
!     br(n) is missing the contribution from its right neighbor
    if (r) then
        do i=1,n
            br(i)=2. /(lr*bh(i))
        enddo
        br(0)=bm(n)
    endif

    call rzero(g,(n+1)*(n+1))
    do j=1,n-1
        do i=1,n-1
            do k=b0,b1
                g(i,j) = g(i,j) + gmm*jgl(i,k)*bm(k)*jgl(j,k)
            enddo
        enddo
    enddo

    if (l) then
        do i=1,n-1
            g(i,0) = glm*jgl(i,0)*bm(0)*jgl(n-1,n)
            g(0,i) = g(i,0)
        enddo
    !        the following is inexact
    !        the neighbors bc's are ignored, and the contribution
    !        from the neighbor's neighbor is left out
    !        that is, bl(0) could be off as noted above
    !        or maybe i should go from 1 to n
        do i=0,n
            g(0,0) = g(0,0) + gll*jgl(n-1,i)*bl(i)*jgl(n-1,i)
        enddo
    else
        g(0,0)=1.
    endif

    if (r) then
        do i=1,n-1
            g(i,n) = gmr*jgl(i,n)*bm(n)*jgl(1,0)
            g(n,i) = g(i,n)
        enddo
    !        the following is inexact
    !        the neighbors bc's are ignored, and the contribution
    !        from the neighbor's neighbor is left out
    !        that is, br(n) could be off as noted above
    !        or maybe i should go from 0 to n-1
        do i=0,n
            g(n,n) = g(n,n) + grr*jgl(1,i)*br(i)*jgl(1,i)
        enddo
    else
        g(n,n)=1.
    endif
    return
    end subroutine set_up_fast_1D_sem_op
!-----------------------------------------------------------------------
subroutine swap_lengths()
  use kinds, only : DP
  use size_m, only : lx1, ly1, lz1, lelv
  use size_m, only : nx1, nelv, lelt
  use geom, only : xm1, ym1, zm1
  use input, only : if3d
  use wz_m, only : wxm1
  implicit none

  real, allocatable :: l(:,:,:,:)
  common /ctmpf/  lr(2*lx1+4),ls(2*lx1+4),lt(2*lx1+4) &
  , llr(lelt),lls(lelt),llt(lelt) &
  , lmr(lelt),lms(lelt),lmt(lelt) &
  , lrr(lelt),lrs(lelt),lrt(lelt)
  real(DP) :: lr ,ls ,lt
  real(DP) :: llr,lls,llt
  real(DP) :: lmr,lms,lmt
  real(DP) :: lrr,lrs,lrt

  real :: l2d
  integer :: e, n2, nz0, nzn, nx, n, j, k

  allocate(l(lx1, ly1, lz1, lelv))

  n2 = nx1-1
  nz0 = 1
  nzn = 1
  nx  = nx1-2
  if (if3d) then
      nz0 = 0
      nzn = n2
  endif
  call plane_space(lmr,lms,lmt,0,n2,wxm1,xm1,ym1,zm1,nx,n2,nz0,nzn)

  n=n2+1
  if (if3d) then
      do e=1,nelv
          do j=2,n2
              do k=2,n2
                  l(1,k,j,e) = lmr(e)
                  l(n,k,j,e) = lmr(e)
                  l(k,1,j,e) = lms(e)
                  l(k,n,j,e) = lms(e)
                  l(k,j,1,e) = lmt(e)
                  l(k,j,n,e) = lmt(e)
              enddo
          enddo
      enddo
      call dssum(l,n,n,n)
      do e=1,nelv
          llr(e) = l(1,2,2,e)-lmr(e)
          lrr(e) = l(n,2,2,e)-lmr(e)
          lls(e) = l(2,1,2,e)-lms(e)
          lrs(e) = l(2,n,2,e)-lms(e)
          llt(e) = l(2,2,1,e)-lmt(e)
          lrt(e) = l(2,2,n,e)-lmt(e)
      enddo
  else
      do e=1,nelv
          do j=2,n2
              l(1,j,1,e) = lmr(e)
              l(n,j,1,e) = lmr(e)
              l(j,1,1,e) = lms(e)
              l(j,n,1,e) = lms(e)
          !           call outmat(l(1,1,1,e),n,n,' L    ',e)
          enddo
      enddo
  !        call outmat(l(1,1,1,25),n,n,' L    ',25)
      call dssum(l,n,n,1)
  !        call outmat(l(1,1,1,25),n,n,' L    ',25)
      do e=1,nelv
      !           call outmat(l(1,1,1,e),n,n,' L    ',e)
          llr(e) = l(1,2,1,e)-lmr(e)
          lrr(e) = l(n,2,1,e)-lmr(e)
          lls(e) = l(2,1,1,e)-lms(e)
          lrs(e) = l(2,n,1,e)-lms(e)
      enddo
  endif
  return
end subroutine swap_lengths
!----------------------------------------------------------------------
    subroutine row_zero(a,m,n,e)
    integer :: m,n,e
    real :: a(m,n)
    do j=1,n
        a(e,j)=0.
    enddo
    return
    end subroutine row_zero
!-----------------------------------------------------------------------
!> \brief Reorder vector using temporary buffer
subroutine swap(b,ind,n,temp)
  implicit none
  real :: B(1),TEMP(1)
  integer :: n, IND(1)
  integer :: i, jj

!***
!***  SORT ASSOCIATED ELEMENTS BY PUTTING ITEM(JJ)
!***  INTO ITEM(I), WHERE JJ=IND(I).
!***
  DO I=1,N
      JJ=IND(I)
      TEMP(I)=B(JJ)
  END DO
  DO I=1,N
      B(I)=TEMP(I)
  END DO
  RETURN
end subroutine swap

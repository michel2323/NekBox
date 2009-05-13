c-----------------------------------------------------------------------
c
      subroutine set_vert(glo_num,ngv,nx,nel,melg,vertex,ifcenter)
c
c
c     Given global array, vertex, pointing to hex vertices, set up
c     a new array of global pointers for an nx^ndim set of elements.
c
c     No communication required, because vertex has all the data.
c
c     The output can go straight into gs_init:
c
c         call        gs_init_vec_sz(ndim)
c         gs_handle = gs_init(glo_num,n,NP)
c
c     where n := nx^ndim * nel.
c
c
      include 'SIZE'
      include 'INPUT'
c
      integer glo_num(1),vertex(1),ngv,nx
      logical ifcenter

      if (if3d) then
         call setvert3d(glo_num,ngv,nx,nel,vertex,ifcenter)
      else
         call setvert2d(glo_num,ngv,nx,nel,vertex,ifcenter)
      endif

      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine crs_solve_l2(uf,vf)
c
c     Given an input vector v, this generates the H1 coarse-grid solution
c
      include 'SIZE'
      include 'DOMAIN'
      include 'ESOLV'
      include 'GEOM'
      include 'PARALLEL'
      include 'SOLN'
      include 'INPUT'
      real uf(1),vf(1)
      common /scrpre/ uc(lcr*lelt),w(2*lx1*ly1*lz1)



      call map_f_to_c_l2_bilin(uf,vf,w)
      call crs_solve(xxth,uc,uf)
      call map_c_to_f_l2_bilin(uf,uc,w)

      return
      end
c
c-----------------------------------------------------------------------
c      subroutine test_h1_crs
c      include 'SIZE'
c      include 'DOMAIN'
c      common /scrxxt/ x(lcr*lelv),b(lcr*lelv)
c      common /nekmpi/ mid,mp,nekcomm,nekgroup,nekreal
c      real x,b
c      ntot=nelv*nxyz_c
c      do i=1,12
c         call rzero(b,ntot)
c         if(mp.eq.1) then
c            b(i)=1
c         else if(mid.eq.0) then
c            if(i.gt.8) b(i-8)=1
c         else
c            if(i.le.8) b(i)=1
c         endif
c         call hsmg_coarse_solve(x,b)
c         print *, 'Column ',i,':',(x(j),j=1,ntot)
c      enddo
c      return
c      end
c-----------------------------------------------------------------------
c
      subroutine set_up_h1_crs

      include 'SIZE'
      include 'GEOM'
      include 'DOMAIN'
      include 'INPUT'
      include 'PARALLEL'
      common /nekmpi/ mid,mp,nekcomm,nekgroup,nekreal

      common /ivrtx/ vertex ((2**ldim)*lelt)
      integer vertex

      integer gs_handle
      integer null_space,e

      character*3 cb
      common /scrxxt/ cmlt(lcr,lelv),mask(lcr,lelv)
      common /scrxxti/ ia(lcr,lcr,lelv), ja(lcr,lcr,lelv)
      real mask
      integer ia,ja
      real z

      integer key(2),aa(2)
      common /scrch/ iwork(2,lx1*ly1*lz1*lelv)
      common /scrns/ w(7*lx1*ly1*lz1*lelv)
      common /vptsol/ a(27*lx1*ly1*lz1*lelv)
      integer w
      real wr(1)
      equivalence (wr,w)

      common /scrvhx/ h1(lx1*ly1*lz1*lelv),h2(lx1*ly1*lz1*lelv)
      common /scrmgx/ w1(lx1*ly1*lz1*lelv),w2(lx1*ly1*lz1*lelv)

      if(nid.eq.0) write(6,*) 'setup h1 coarse grid'

      t0 = dnekclock()

c     nxc is order of coarse grid space + 1, nxc=2, linear, 3=quad,etc.
c     nxc=param(82)
c     if (nxc.gt.lxc) then
c        nxc=lxc
c        write(6,*) 'WARNING :: coarse grid space too large',nxc,lxc 
c     endif
c     if (nxc.lt.2) nxc=2

      nxc     = 2
      nx_crs  = nxc

      ncr     = nxc**ndim
      nxyz_c  = ncr
c
c     Set SEM_to_GLOB
c
      call get_vertex
      call set_vert(se_to_gcrs,ngv,nxc,nelv,nelgv,vertex,.true.)

c     Set mask
      z=0
      ntot=nelv*nxyz_c
      nzc=1
      if (if3d) nzc=nxc
      call rone(mask,ntot)
      call rone(cmlt,ntot)
      nfaces=2*ndim
      ifield=1

      do ie=1,nelv
      do iface=1,nfaces
         cb=cbc(iface,ie,ifield)
         if (cb.eq.'O  '  .or.
     $       cb.eq.'ON '  .or.
     $       cb.eq.'MS ') call facev(mask,ie,iface,z,nxc,nxc,nzc)
      enddo
      enddo

c     Set global index of dirichlet nodes to zero; xxt will ignore them

      call gs_setup(gs_handle,se_to_gcrs,ntot,nekcomm,mp)
      call gs_op   (gs_handle,mask,1,2,0)  !  "*"
      call gs_op   (gs_handle,cmlt,1,1,0)  !  "+"
      call gs_free (gs_handle)
      call set_jl_crs_mask(ntot,mask,se_to_gcrs)

      call invcol1(cmlt,ntot)

c     Setup local SEM-based Neumann operators (for now, just full...)

      if (param(51).eq.1) then     ! old coarse grid
         nxyz1=nx1*ny1*nz1
         lda = 27*nxyz1*lelt
         ldw =  7*nxyz1*lelt
         call get_local_crs(a,lda,nxc,h1,h2,w,ldw)
      else
c        NOTE: a(),h1,...,w2() must all be large enough
         n = nx1*ny1*nz1*nelv
         call rone (h1,n)
         call rzero(h2,n)
         call get_local_crs_galerkin(a,ncr,nxc,h1,h2,w1,w2)
      endif

      call set_mat_ij(ia,ja,ncr,nelv)
      null_space=0
      if (ifvcor) null_space=1

      nz=ncr*ncr*nelv
      call crs_setup(xxth,nekcomm,mp, ntot,se_to_gcrs,
     $               nz,ia,ja,a, null_space)
c     call crs_stats(xxth)

      t0 = dnekclock()-t0
      if (nid.eq.0) then
         write(6,*) '  set_up_h1_crs time:',t0,' seconds'
         write(6,*) 'done :: setup h1 coarse grid'
         write(6,*) ' '
      endif

      return
      end
c
c-----------------------------------------------------------------------
      subroutine set_jl_crs_mask(n, mask, se_to_gcrs)
      integer n
      real mask(n)
      integer se_to_gcrs(n)
      do i=1,n
         if(mask(i).lt.0.1) se_to_gcrs(i)=0
      enddo
      return
      end
c-----------------------------------------------------------------------
      subroutine set_mat_ij(ia,ja,n,ne)
      integer n,ne
      integer ia(n,n,ne), ja(n,n,ne)
c
      integer i,j,ie
      do ie=1,ne
      do j=1,n
      do i=1,n
         ia(i,j,ie)=(ie-1)*n+i-1
         ja(i,j,ie)=(ie-1)*n+j-1
      enddo
      enddo
      enddo
      return
      end
c-----------------------------------------------------------------------
c
      subroutine set_up_enriched_crs
c
c     Build:
c
c     se_to_lcrs
c     se_to_gcrs
c     mask 
c     sem_crs_A_mat   (a)
c     tensor-product prolongation/restriction
c
c
      include 'SIZE'
      include 'DOMAIN'
      include 'INPUT'
      include 'PARALLEL'

      common /ivrtx/ vertex ((2**ldim)*lelt)
      integer vertex

      integer key(2),aa(2)
      common /scrch/ iwork(2,lx1*ly1*lz1*lelv)
      common /scrns/ w(7*lx1*ly1*lz1*lelv)
      common /vptsol/ a(27*lx1*ly1*lz1*lelv)
      integer w

      real wr(1)
      equivalence (wr,w)
c
      real h1(1),h2(1)
c
c     nxc is order of coarse grid space + 1, nxc=2, linear, 3=quad,etc.
c
      nxc=param(82)
      if (nxc.gt.lxc) then
         nxc=lxc
         write(6,*) 'WARNING :: coarse grid space too large',nxc,lxc 
      endif
      if (nxc.lt.2) nxc=2
      nx_crs = nxc
c
      ncr  =nxc**ndim
      nxyz_c  = ncr
c
c     Set SEM_to_GLOB
c
      call get_vertex
      call set_vert(se_to_gcrs,ngv,nxc,nelv,nelgv,vertex,.true.)
c
c     Set SEM_to_LOC
c
      ntot=nelv*nxyz_c
      do i=1,ntot
         iwork(1,i) = se_to_gcrs(i,1)
         iwork(2,i) = 0
      enddo
      key(1)=1
      key(2)=2
      call irank_vec(se_to_lcrs,ndofs,iwork,2,ntot,key,2,aa)
c
c     call out_se(se_to_lcrs,nxc,'lb4m')
c     call out_se(se_to_gcrs,nxc,'gb4m')
c     call exitt
c
c     Set masks
      call set_crs_mask(se_to_lcrs,ngvm,mask_offset,nxc,ndofs,w)
c      write(6,*) 'this is ngvm',ngvm,ndofs,mask_offset,ngv
      n_crs=ngvm
c
c
c     Set loc_to_glob, accounting for mask
      call set_loc2glob_crs(w,nxc,n_crs)
c
c     Setup local SEM-based Neumann operators (for now, just full...)
      nxyz1=nx1*ny1*nz1
      lda = 27*nxyz1*lelt
      ldw =  7*nxyz1*lelt
      call get_local_crs(a,lda,nxc,h1,h2,w,ldw)
c      write(6,*) 'this is ngv:',ngv
c
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine irank_vec(ind,nn,a,m,n,key,nkey,aa)
c
c     Compute rank of each unique entry a(1,i) 
c
c     Output:   ind(i)  i=1,...,n    (global) rank of entry a(*,i)
c               nn  = max(rank)
c               a(j,i) is destroyed
c
c     Input:    a(j,i) j=1,...,m;  i=1,...,n  
c               m      :   leading dim. of v  (ldv must be .ge. m)
c               key    :   sort key
c               nkey   :   
c
c     Although not mandatory, this ranking procedure is probably
c     most effectively employed when the keys are pre-sorted. Thus,
c     the option is provided to sort vi() prior to the ranking.
c
c
      integer ind(n),a(m,n)
      integer key(nkey),aa(m)
      logical iftuple_ianeb,a_ne_b
c
      if (m.eq.1) then
c
         write(6,*) 
     $        'WARNING: For single key, not clear that rank is unique!'
         call irank(a,ind,n)
         return
      endif
c
c
      nk = min(nkey,m)
      call ituple_sort(a,m,n,key,nk,ind,aa)
c
c     Find unique a's
c
      nn=1
c
      call icopy(aa,a,m)
      a(1,1) = nn
      a(2,1)=ind(1)
c
      do i=2,n
         a_ne_b = iftuple_ianeb(aa,a(1,i),key,nk)
         if (a_ne_b) then
            call icopy(aa,a(1,i),m)
            nn = nn+1
         endif
         a(1,i) = nn
         a(2,i) = ind(i)
      enddo
c
c     Set ind() to rank
c
      do i=1,n
         iold=a(2,i)
         ind(iold) = a(1,i)
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine ituple_sort(a,lda,n,key,nkey,ind,aa)
C
C     Use Heap Sort (p 231 Num. Rec., 1st Ed.)
C
      integer a(lda,n),aa(lda)
      integer ind(1),key(nkey)
      logical iftuple_ialtb
C
      dO 10 j=1,n
         ind(j)=j
   10 continue
C
      if (n.le.1) return
      L=n/2+1
      ir=n
  100 continue
         if (l.gt.1) then
            l=l-1
c           aa  = a  (l)
            call icopy(aa,a(1,l),lda)
            ii  = ind(l)
         else
c           aa =   a(ir)
            call icopy(aa,a(1,ir),lda)
            ii = ind(ir)
c           a(ir) =   a( 1)
            call icopy(a(1,ir),a(1,1),lda)
            ind(ir) = ind( 1)
            ir=ir-1
            if (ir.eq.1) then
c              a(1) = aa
               call icopy(a(1,1),aa,lda)
               ind(1) = ii
               return
            endif
         endif
         i=l
         j=l+l
  200    continue
         if (j.le.ir) then
            if (j.lt.ir) then
               if (iftuple_ialtb(a(1,j),a(1,j+1),key,nkey)) j=j+1
            endif
            if (iftuple_ialtb(aa,a(1,j),key,nkey)) then
c              a(i) = a(j)
               call icopy(a(1,i),a(1,j),lda)
               ind(i) = ind(j)
               i=j
               j=j+j
            else
               j=ir+1
            endif
         GOTO 200
         endif
c        a(i) = aa
         call icopy(a(1,i),aa,lda)
         ind(i) = ii
      GOTO 100
      end
c
c-----------------------------------------------------------------------
c
      subroutine tuple_sort(a,lda,n,key,nkey,ind,aa)
C
C     Use Heap Sort (p 231 Num. Rec., 1st Ed.)
C
      real a(lda,n),aa(lda)
      integer ind(1),key(nkey)
      logical iftuple_altb
C
      dO 10 j=1,n
         ind(j)=j
   10 continue
C
      if (n.le.1) return
      L=n/2+1
      ir=n
  100 continue
         if (l.gt.1) then
            l=l-1
c           aa  = a  (l)
            call copy(aa,a(1,l),lda)
            ii  = ind(l)
         else
c           aa =   a(ir)
            call copy(aa,a(1,ir),lda)
            ii = ind(ir)
c           a(ir) =   a( 1)
            call copy(a(1,ir),a(1,1),lda)
            ind(ir) = ind( 1)
            ir=ir-1
            if (ir.eq.1) then
c              a(1) = aa
               call copy(a(1,1),aa,lda)
               ind(1) = ii
               return
            endif
         endif
         i=l
         j=l+l
  200    continue
         if (j.le.ir) then
            if (j.lt.ir) then
c              if ( a(j).lt.a(j+1) ) j=j+1
               if (iftuple_altb(a(1,j),a(1,j+1),key,nkey)) j=j+1
            endif
c           if (aa.lt.a(j)) then
            if (iftuple_altb(aa,a(1,j),key,nkey)) then
c              a(i) = a(j)
               call copy(a(1,i),a(1,j),lda)
               ind(i) = ind(j)
               i=j
               j=j+j
            else
               j=ir+1
            endif
         GOTO 200
         endif
c        a(i) = aa
         call copy(a(1,i),aa,lda)
         ind(i) = ii
      GOTO 100
      end
c
c-----------------------------------------------------------------------
c
      logical function iftuple_ialtb(a,b,key,nkey)
      integer a(1),b(1)
      integer key(nkey)
c
      do i=1,nkey
         k=key(i)
         if (a(k).lt.b(k)) then
            iftuple_ialtb = .true.
            return
         elseif (a(k).gt.b(k)) then
            iftuple_ialtb = .false.
            return
         endif
      enddo
      iftuple_ialtb = .false.
      return
      end
c
c-----------------------------------------------------------------------
c
      logical function iftuple_altb(a,b,key,nkey)
      real a(1),b(1)
      integer key(nkey)
c
      do i=1,nkey
         k=key(i)
         if (a(k).lt.b(k)) then
            iftuple_altb = .true.
            return
         elseif (a(k).gt.b(k)) then
            iftuple_altb = .false.
            return
         endif
      enddo
      iftuple_altb = .false.
      return
      end
c
c-----------------------------------------------------------------------
c
      logical function iftuple_ianeb(a,b,key,nkey)
      integer a(1),b(1)
      integer key(nkey)
c
      do i=1,nkey
         k=key(i)
         if (a(k).ne.b(k)) then
            iftuple_ianeb = .true.
            return
         endif
      enddo
      iftuple_ianeb = .false.
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine get_local_crs(a,lda,nxc,h1,h2,w,ldw)
c
c     This routine generates Nelv submatrices of order nxc^ndim.
c
      include 'SIZE'
      include 'GEOM'
      include 'INPUT'
      include 'TSTEP'
      include 'DOMAIN'
      include 'PARALLEL'
c
c
c     Generate local triangular matrix
c
      real   a(1),h1(1),h2(1),w(ldw)
c
      parameter (lcrd=lx1**ldim)
      common /ctmp1/ x(lcrd),y(lcrd),z(lcrd)
c
c
      ncrs_loc = nxc**ndim
      n2       = ncrs_loc*ncrs_loc
c
c     Required storage for a:
      nda = n2*nelv
      if (nda.gt.lda) then
         write(6,*)nid,'ERROR: increase storage get_local_crs:',nda,lda
         call exitt
      endif
c
c
      l = 1
      do ie=1,nelv
c
         call map_to_crs(x,nxc,xm1(1,1,1,ie),nx1,if3d,w,ldw)
         call map_to_crs(y,nxc,ym1(1,1,1,ie),nx1,if3d,w,ldw)
         if (if3d) call map_to_crs(z,nxc,zm1(1,1,1,ie),nx1,if3d,w,ldw)
c.later. call map_to_crs(hl1,nxc,h1(1,1,1,ie),nx1,if3d,w,ldw)
c.later. call map_to_crs(hl2,nxc,h2(1,1,1,ie),nx1,if3d,w,ldw)
c
         call a_crs_enriched(a(l),h1,h2,x,y,z,nxc,if3d,ie)
         l=l+n2
c
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine a_crs_enriched(a,h1,h2,x1,y1,z1,nxc,if3d,ie)
c
c     This sets up a matrix for a single array of tensor-product
c     gridpoints (e.g., an array defined by SEM-GLL vertices)
c
c         For example, suppose ndim=3.
c
c         Then, there would be ncrs_loc := nxc^3 dofs for this matrix,
c
c         and the matrix size would be (ncrs_loc x ncrs_loc).
c
c
c
      include 'SIZE'
c
      real a(1),h1(1),h2(1)
      real x1(nxc,nxc,1),y1(nxc,nxc,1),z1(nxc,nxc,1)
      logical if3d
c
      parameter (ldm2=2**ldim)
      real a_loc(ldm2,ldm2)
      real x(8),y(8),z(8)
c
      ncrs_loc = nxc**ndim
      n2       = ncrs_loc*ncrs_loc
      call rzero(a,n2)
c
      nyc=nxc
      nzc=2
      if (if3d) nzc=nxc
      nz =0
      if (if3d) nz=1
c
c     Here, we march across sub-cubes
c
      do kz=1,nzc-1
      do ky=1,nyc-1
      do kx=1,nxc-1
         k = 0
         do iz=0,nz
         do iy=0,1
         do ix=0,1
            k = k+1
            x(k) = x1(kx+ix,ky+iy,kz+iz)
            y(k) = y1(kx+ix,ky+iy,kz+iz)
            z(k) = z1(kx+ix,ky+iy,kz+iz)
         enddo
         enddo
         enddo
         if (if3d) then
            call a_crs_3d(a_loc,h1,h2,x,y,z,ie)
         else
            call a_crs_2d(a_loc,h1,h2,x,y,ie)
         endif
c        call outmat(a_loc,ldm2,ldm2,'A_loc ',ie)
c
c        Assemble:
c
         j = 0
         do jz=0,nz
         do jy=0,1
         do jx=0,1
            j = j+1
            ja = (kx+jx) + nxc*(ky+jy-1) + nxc*nyc*(kz+jz-1)
c
            i = 0
            do iz=0,nz
            do iy=0,1
            do ix=0,1
               i   = i+1
               ia  = (kx+ix) + nxc*(ky+iy-1) + nxc*nyc*(kz+iz-1)
c
               ija = ia + ncrs_loc*(ja-1)
               a(ija) = a(ija) + a_loc(i,j)
c
            enddo
            enddo
            enddo
c
         enddo
         enddo
         enddo
      enddo
      enddo
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine a_crs_3d(a,h1,h2,xc,yc,zc,ie)
c
c     Generate stiffness matrix for 3D coarse grid problem.
c     
c     This is done by using two tetrahedrizations of each
c     hexahedral subdomain (element) such that each of the
c     6 panels (faces) on the sides of an element has a big X.
c
c
      real a(0:7,0:7),h1(0:7),h2(0:7)
      real xc(0:7),yc(0:7),zc(0:7)
c
      real a_loc(4,4)
      real xt(4),yt(4),zt(4)
c
      integer vertex(4,5,2)
      save    vertex
      data    vertex / 000 ,  001 , 010 , 100
     $               , 000 ,  001 , 011 , 101 
     $               , 011 ,  010 , 000 , 110 
     $               , 011 ,  010 , 001 , 111 
     $               , 000 ,  110 , 101 , 011
c
     $               , 101 ,  100 , 110 , 000
     $               , 101 ,  100 , 111 , 001 
     $               , 110 ,  111 , 100 , 010 
     $               , 110 ,  111 , 101 , 011 
     $               , 111 ,  001 , 100 , 010  /
c
      integer icalld
      save    icalld
      data    icalld/0/
c
      if (icalld.eq.0) then
         do i=1,40
            call bindec(vertex(i,1,1))
         enddo
      endif
      icalld=icalld+1
c
      call rzero(a,64)
      do k=1,10
         do iv=1,4
            xt(iv) = xc(vertex(iv,k,1))
            yt(iv) = yc(vertex(iv,k,1))
            zt(iv) = zc(vertex(iv,k,1))
         enddo
         call get_local_A_tet(a_loc,xt,yt,zt,k,ie)
         do j=1,4
            jj = vertex(j,k,1)
            do i=1,4
               ii = vertex(i,k,1)
               a(ii,jj) = a(ii,jj) + 0.5*a_loc(i,j)
            enddo
         enddo
      enddo
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine bindec(bin_in)
      integer bin_in,d,b,b2
c
      keep  = bin_in
      d  = bin_in
      b2 = 1
      b  = 0
      do l=1,12
         b  = b + b2*mod(d,10)
         d  = d/10
         b2 = b2*2
         if (d.eq.0) goto 1
      enddo
    1 continue
      bin_in = b
      return
      end
c
c-----------------------------------------------------------------------
      subroutine get_local_A_tet(a,x,y,z,kt,ie)
c
c     Generate local tetrahedral matrix
c
c
      real a(4,4), g(4,4)
      real x(4),y(4),z(4)
c
   11 continue
      x23 = x(2) - x(3)
      y23 = y(2) - y(3)
      z23 = z(2) - z(3)
      x34 = x(3) - x(4)
      y34 = y(3) - y(4)
      z34 = z(3) - z(4)
      x41 = x(4) - x(1)
      y41 = y(4) - y(1)
      z41 = z(4) - z(1)
      x12 = x(1) - x(2)
      y12 = y(1) - y(2)
      z12 = z(1) - z(2)
c
      xy234 = x34*y23 - x23*y34
      xy341 = x34*y41 - x41*y34
      xy412 = x12*y41 - x41*y12
      xy123 = x12*y23 - x23*y12
      xz234 = x23*z34 - x34*z23
      xz341 = x41*z34 - x34*z41
      xz412 = x41*z12 - x12*z41
      xz123 = x23*z12 - x12*z23
      yz234 = y34*z23 - y23*z34
      yz341 = y34*z41 - y41*z34
      yz412 = y12*z41 - y41*z12
      yz123 = y12*z23 - y23*z12
c
      g(1,1) = -(x(2)*yz234 + y(2)*xz234 + z(2)*xy234)
      g(2,1) = -(x(3)*yz341 + y(3)*xz341 + z(3)*xy341)
      g(3,1) = -(x(4)*yz412 + y(4)*xz412 + z(4)*xy412)
      g(4,1) = -(x(1)*yz123 + y(1)*xz123 + z(1)*xy123)
      g(1,2) = yz234
      g(2,2) = yz341
      g(3,2) = yz412
      g(4,2) = yz123
      g(1,3) = xz234
      g(2,3) = xz341
      g(3,3) = xz412
      g(4,3) = xz123
      g(1,4) = xy234
      g(2,4) = xy341
      g(3,4) = xy412
      g(4,4) = xy123
c
c        vol36 = 1/(36*volume) = 1/(6*determinant)
c
      det = x(1)*yz234 + x(2)*yz341 + x(3)*yz412 + x(4)*yz123
      vol36 = 1.0/(6.0*det)
      if (vol36.lt.0) then
         write(6,*) 'Error: tetrahedron not right-handed',ie
         write(6,1) 'x',(x(k),k=1,4)
         write(6,1) 'y',(y(k),k=1,4)
         write(6,1) 'z',(z(k),k=1,4)
 1       format(a1,1p4e15.5)

c        call exitt                 ! Option 1

         xx = x(1)                  ! Option 2
         x(1) = x(2)                !  -- this is the option that 
         x(2) = xx                  !     actually works. 11/25/07

         xx = y(1)
         y(1) = y(2)
         y(2) = xx

         xx = z(1)
         z(1) = z(2)
         z(2) = xx

         goto 11

c        call rzero(a,16)           ! Option 3
c        return

c        vol36 = abs(vol36)         ! Option 4

      endif
c
      do j=1,4
         do i=1,4
            a(i,j)=vol36*(g(i,2)*g(j,2)+g(i,3)*g(j,3)+g(i,4)*g(j,4))
         enddo
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine a_crs_2d(a,h1,h2,x,y,ie)
c
      include 'SIZE'
      include 'GEOM'
      include 'INPUT'
      include 'TSTEP'
      include 'DOMAIN'
      include 'PARALLEL'
c
c     Generate local triangle-based stiffnes matrix for quad
c
      real a(4,4),h1(1),h2(1)
      real x(1),y(1)
c
c     Triangle to Square pointers
c
      integer elem(3,2)
      save    elem
      data    elem / 1,2,4  ,  1,4,3 /
c
      real a_loc(3,3)
c
c
      call rzero(a,16)
c
      do i=1,2
         j1 = elem(1,i)
         j2 = elem(2,i)
         j3 = elem(3,i)
         x1=x(j1)
         y1=y(j1)
         x2=x(j2)
         y2=y(j2)
         x3=x(j3)
         y3=y(j3)
c
         y23=y2-y3
         y31=y3-y1
         y12=y1-y2
c
         x32=x3-x2
         x13=x1-x3
         x21=x2-x1
c
c        area4 = 1/(4*area)
         area4 = 0.50/(x21*y31 - y12*x13)
c
         a_loc(1, 1) = area4*( y23*y23+x32*x32 )
         a_loc(1, 2) = area4*( y23*y31+x32*x13 )
         a_loc(1, 3) = area4*( y23*y12+x32*x21 )
c
         a_loc(2, 1) = area4*( y31*y23+x13*x32 )
         a_loc(2, 2) = area4*( y31*y31+x13*x13 )
         a_loc(2, 3) = area4*( y31*y12+x13*x21 )
c
         a_loc(3, 1) = area4*( y12*y23+x21*x32 )
         a_loc(3, 2) = area4*( y12*y31+x21*x13 )
         a_loc(3, 3) = area4*( y12*y12+x21*x21 )
c
c        Store in "4 x 4" format
c
         do il=1,3
            iv = elem(il,i)
            do jl=1,3
               jv = elem(jl,i)
               a(iv,jv) = a(iv,jv) + a_loc(il,jl)
            enddo
         enddo
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_to_crs(a,na,b,nb,if3d,w,ldw)
c
c     Input:   b
c     Output:  a
c
      real a(1),b(1),w(1)
      logical if3d
c
      parameter(lx=40)
      real za(lx),zb(lx)
c
      real iba(lx*lx),ibat(lx*lx)
      save iba,ibat
c
      integer nao,nbo
      save    nao,nbo
      data    nao,nbo  / -9, -9/
c
      if (na.gt.lx.or.nb.gt.lx) then
         write(6,*)'ERROR: increase lx in map_to_crs to max:',na,nb
         call exitt
      endif
c
      if (na.ne.nao  .or.   nb.ne.nbo) then
         nao = na
         nbo = nb
         call zwgll(za,w,na)
         call zwgll(zb,w,nb)
         call igllm(iba,ibat,zb,za,nb,na,nb,na)
      endif
c
      call specmpn(a,na,b,nb,iba,ibat,if3d,w,ldw)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine specmpn(b,nb,a,na,ba,ab,if3d,w,ldw)
C
C     -  Spectral interpolation from A to B via tensor products
C     -  scratch arrays: w(na*na*nb + nb*nb*na)
C
C     5/3/00  -- this routine replaces specmp in navier1.f, which
c                has a potential memory problem
C
C
      logical if3d
c
      real b(nb,nb,nb),a(na,na,na)
      real w(ldw)
c
      ltest = na*nb
      if (if3d) ltest = na*na*nb + nb*na*na
      if (ldw.lt.ltest) then
         write(6,*) 'ERROR specmp:',ldw,ltest,if3d
         call exitt
      endif
c
      if (if3d) then
         nab = na*nb
         nbb = nb*nb
         call mxm(ba,nb,a,na,w,na*na)
         k=1
         l=na*na*nb + 1
         do iz=1,na
            call mxm(w(k),nb,ab,na,w(l),nb)
            k=k+nab
            l=l+nbb
         enddo
         l=na*na*nb + 1
         call mxm(w(l),nbb,ab,na,b,nb)
      else
         call mxm(ba,nb,a,na,w,na)
         call mxm(w,nb,ab,na,b,nb)
      endif
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine irank(A,IND,N)
C
C     Use Heap Sort (p 233 Num. Rec.), 5/26/93 pff.
C
      integer A(1),IND(1)
C
      if (n.le.1) return
      DO 10 J=1,N
         IND(j)=j
   10 continue
C
      if (n.eq.1) return
      L=n/2+1
      ir=n
  100 continue
         IF (l.gt.1) THEN
            l=l-1
            indx=ind(l)
            q=a(indx)
         ELSE
            indx=ind(ir)
            q=a(indx)
            ind(ir)=ind(1)
            ir=ir-1
            if (ir.eq.1) then
               ind(1)=indx
               return
            endif
         ENDIF
         i=l
         j=l+l
  200    continue
         IF (J.le.IR) THEN
            IF (J.lt.IR) THEN
               IF ( A(IND(j)).lt.A(IND(j+1)) ) j=j+1
            ENDIF
            IF (q.lt.A(IND(j))) THEN
               IND(I)=IND(J)
               I=J
               J=J+J
            ELSE
               J=IR+1
            ENDIF
         GOTO 200
         ENDIF
         IND(I)=INDX
      GOTO 100
      END
c
c-----------------------------------------------------------------------
c
      subroutine iranku(r,input,n,w,ind)
c
c     Return the rank of each input value, and the maximum rank.
c
c     OUTPUT:    r(k) = rank of each entry,  k=1,..,n
c                maxr = max( r )
c                w(i) = sorted & compressed list of input values
c
      integer r(1),input(1),ind(1),w(1)
c
      call icopy(r,input,n)
      call isort(r,ind,n)
c
      maxr  = 1
      rlast = r(1) 
      do i=1,n
c        Bump rank only when r_i changes
         if (r(i).ne.rlast) then
            rlast = r(i)
            maxr  = maxr + 1
         endif
         r(i) = maxr
      enddo
      call iunswap(r,ind,n,w)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine ifacev_redef(a,ie,iface,val,nx,ny,nz)
C
C     Assign the value VAL to face(IFACE,IE) of array A.
C     IFACE is the input in the pre-processor ordering scheme.
C
      include 'SIZE'
      integer a(nx,ny,nz,lelt),val
      call facind (kx1,kx2,ky1,ky2,kz1,kz2,nx,ny,nz,iface)
      do 100 iz=kz1,kz2
      do 100 iy=ky1,ky2
      do 100 ix=kx1,kx2
         a(ix,iy,iz,ie)=val
  100 continue
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine set_crs_mask(se2lcrs,ngvm,mask_offset,nxc,ndof,w)
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
      include 'PARALLEL'
c
c     Generate masks, and order se_to_lcrs accordingly
c
      integer se2lcrs(1),w(1)
      character*3 cb
c
c
C
C     Pressure mask
C
      nzc=1
      if (if3d) nzc=nxc
      nxyz=nxc**ndim
      ntot=nxyz*nelv
      call ione(w,ntot)
      nfaces=2*ndim
      ifield=1
      do ie=1,nelv
      do iface=1,nfaces
         cb=cbc(iface,ie,ifield)
         if (cb.eq.'O  '  .or.
     $       cb.eq.'ON '  .or.
     $       cb.eq.'MS ') call ifacev(w,ie,iface,0,nxc,nxc,nzc)
      enddo
      enddo
c     Zero out mask at Neumann-Dirichlet interfaces
c     call dsop(pmask,'MUL',nxc,nxc,nzc)         !!! DONT FORGET THIS
c     write(6,*) 'WARNING - DSOP not yet called in set_crs_mask!',nid
c
c
c     Increase each masked entry by mask_offset
c
      mask_offset=ndof+1
      do i=1,ntot
         if (w(i).eq.0) se2lcrs(i)=se2lcrs(i)+mask_offset
      enddo
c
c     unique rank, such that w(1) gives rank of element i
      call iranku(w,se2lcrs,ntot,w(1+ntot),w(1+2*ntot))
c     
      ngvm=0
      do i=1,ntot
         if (se2lcrs(i).lt.mask_offset) then
            ngvm=max(ngvm,w(i))
            se2lcrs(i) = w(i)
         else
            se2lcrs(i) = -w(i)
         endif
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine set_loc2glob_crs(w,nxc,ngv)
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
      include 'PARALLEL'
c
c     Generate loc2glob
c
      integer w(1)
c
      nxyz=nxc**ndim
      ntot=nxyz*nelv
c
      do i=1,ntot
         il = abs(se_to_lcrs(i,1))
         ig =     se_to_gcrs(i,1)
         w(il)=ig
      enddo
c
c     Store loc-2-glob in se_to_gcrs, since we don't need se_to_gcrs
c
      call copy(se_to_gcrs,w,ngv)
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_c_to_f_l2_bilin(uf,uc,w)
c
c     H1 Iterpolation operator:  linear --> spectral GLL mesh
c
      include 'SIZE'
      include 'DOMAIN'
      include 'INPUT'
c
      parameter (lxyz = lx2*ly2*lz2)
      real uc(nxyz_c,lelt),uf(lxyz,lelt),w(1)

      ltot22 = 2*lx2*ly2*lz2
      nx_crs = 2   ! bilinear only

      do ie=1,nelv
         call maph1_to_l2(uf(1,ie),nx2,uc(1,ie),nx_crs,if3d,w,ltot22)
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_f_to_c_l2_bilin(uc,uf,w)

c     TRANSPOSE of L2 Iterpolation operator:                    T
c                                 (linear --> spectral GLL mesh)

      include 'SIZE'
      include 'DOMAIN'
      include 'INPUT'

      parameter (lxyz = lx2*ly2*lz2)
      real uc(nxyz_c,lelt),uf(lxyz,lelt),w(1)

      ltot22 = 2*lx2*ly2*lz2
      nx_crs = 2   ! bilinear only

      do ie=1,nelv
         call maph1_to_l2t(uc(1,ie),nx_crs,uf(1,ie),nx2,if3d,w,ltot22)
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine maph1_to_l2(a,na,b,nb,if3d,w,ldw)
c
c     Input:   b
c     Output:  a
c
      real a(1),b(1),w(1)
      logical if3d
c
      parameter(lx=40)
      real za(lx),zb(lx)
c
      real iba(lx*lx),ibat(lx*lx)
      save iba,ibat
c
      integer nao,nbo
      save    nao,nbo
      data    nao,nbo  / -9, -9/
c
c
      if (na.gt.lx.or.nb.gt.lx) then
         write(6,*)'ERROR: increase lx in maph1_to_l2 to max:',na,nb
         call exitt
      endif
c
      if (na.ne.nao  .or.   nb.ne.nbo) then
         nao = na
         nbo = nb
         call zwgl (za,w,na)
         call zwgll(zb,w,nb)
         call igllm(iba,ibat,zb,za,nb,na,nb,na)
      endif
c
      call specmpn(a,na,b,nb,iba,ibat,if3d,w,ldw)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine maph1_to_l2t(b,nb,a,na,if3d,w,ldw)
c
c     Input:   a
c     Output:  b
c
      real a(1),b(1),w(1)
      logical if3d
c
      parameter(lx=40)
      real za(lx),zb(lx)
c
      real iba(lx*lx),ibat(lx*lx)
      save iba,ibat
c
      integer nao,nbo
      save    nao,nbo
      data    nao,nbo  / -9, -9/
c
c
      if (na.gt.lx.or.nb.gt.lx) then
         write(6,*)'ERROR: increase lx in maph1_to_l2 to max:',na,nb
         call exitt
      endif
c
      if (na.ne.nao  .or.   nb.ne.nbo) then
         nao = na
         nbo = nb
         call zwgl (za,w,na)
         call zwgll(zb,w,nb)
         call igllm(iba,ibat,zb,za,nb,na,nb,na)
      endif
c
      call specmpn(b,nb,a,na,ibat,iba,if3d,w,ldw)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_c_to_f_l2(uf,uc_in)
c
c     L2 Iterpolation operator:  H1-linear --> spectral GL mesh
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
      include 'SOLN'
c
      parameter (lxyz = lx2*ly2*lz2)
      real uc_in(1),uf(lxyz,lelt)
      common /screc/ uc(lcr*lelt),w(2*lx2*ly2*lz2)
c
c
c     Map to coarse tensor product form
c
      do i=1,nxyz_c*nelv
         j = se_to_lcrs(i,1)
         if (j.gt.0) then
            uc(i) = uc_in(j)
         else
            uc(i) = 0.
         endif
      enddo
      call map_c_to_f_l2_bilin(uf,uc,w)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_f_to_c_l2(uc_out,uf)
c
c     TRANSPOSE of L2 Iterpolation operator:                    T
c                                 (linear --> spectral GL mesh)
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
      include 'GEOM'
      real uc_out(1),uf(1)
c
      parameter (lxyz = lx2*ly2*lz2)
      common /screc/ uc(lcr*lelt),w(2*lxyz)
c
      call map_f_to_c_l2_bilin(uc,uf,w)
c
c     Map from coarse tensor product form to reduced coarse form
      call rzero(uc_out,n_crs)
      do i=1,nxyz_c*nelv
         j = se_to_lcrs(i,1)
         if (j.gt.0) uc_out(j) = uc_out(j) + uc(i)
      enddo
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine irank_vec_tally(ind,nn,a,m,n,key,nkey,key2,aa)
c
c     Compute rank of each unique entry a(1,i) 
c
c     Output:   ind(i)  i=1,...,n    (global) rank of entry a(*,i)
c               nn  = max(rank)
c               a(j,i) is destroyed
c               a(1,i) tally of preceding structure values
c
c     Input:    a(j,i) j=1,...,m;  i=1,...,n  
c               m      :   leading dim. of v  (ldv must be .ge. m)
c               key    :   sort key
c               nkey   :   
c
c     Although not mandatory, this ranking procedure is probably
c     most effectively employed when the keys are pre-sorted. Thus,
c     the option is provided to sort vi() prior to the ranking.
c
c
      integer ind(n),a(m,n)
      integer key(nkey),key2(0:3),aa(m)
      logical iftuple_ianeb,a_ne_b
c
c
      nk = min(nkey,m)
      call ituple_sort(a,m,n,key,nk,ind,aa)
c     do i=1,n
c        write(6,*) i,' sort:',(a(k,i),k=1,3)
c     enddo
c
c
c     Find unique a's
c
      call icopy(aa,a,m)
      nn=1
      mm=0
c
      a(1,1) = nn
      a(2,1)=ind(1)
      a(3,1)=mm
c
      do i=2,n
         a_ne_b = iftuple_ianeb(aa,a(1,i),key,nk)
         if (a_ne_b) then              ! new structure
            ms = aa(3)                 ! structure type
            if (aa(2).eq.0) ms = aa(2) ! structure type
            mm = mm+key2(ms)           ! n dofs
            call icopy(aa,a(1,i),m)
            nn = nn+1
         endif
         a(1,i) = nn
         a(2,i) = ind(i)
         a(3,i) = mm
      enddo
      ms = aa(3)
      if (aa(2).eq.0) ms = aa(2) ! structure type
      nn = mm+key2(ms)
c
c     Set ind() to rank
c
      do i=1,n
         iold=a(2,i)
         ind(iold) = a(1,i)
      enddo
c
c     Set a1() to number of preceding dofs
c
      do i=1,n
         iold=a(2,i)
         a(1,iold) = a(3,i)
      enddo
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine out_se1(se2crs,nx,name)
c
      include 'SIZE'
      integer se2crs(nx,nx,1)
      character*4 name
c
      write(6,*) 
      write(6,*) 'out_se',nx,name
      do ie=nelv-1,1,-2
         write(6,*)
         do j=nx,1,-1
            if(nx.eq.4) then
               write(6,4) name,((se2crs(i,j,k+ie),i=1,nx),k=0,1)
            elseif(nx.eq.3) then
               write(6,3) name,((se2crs(i,j,k+ie),i=1,nx),k=0,1)
            else
               write(6,2) name,((se2crs(i,j,k+ie),i=1,nx),k=0,1)
            endif
         enddo
      enddo
c
    4 format(a4,5x,2(4i5,3x))
    3 format(a4,5x,2(3i5,3x))
    2 format(a4,5x,2(2i5,3x))
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine out_se(se2crs,nx,name)
c
      include 'SIZE'
      include 'PARALLEL'
      common  /ctmp0/ iw(lx1*ly1*lz1*lelv)
     $              , jw(lx1*ly1*lz1*lelv)
c
      integer se2crs(nx,nx,1)
      character*4 name
c
c     if (np.eq.1) then
c        call out_se1(se2crs,nx,name)
c        return
c     endif
c
      nxyz =nx**ndim
      ntotg=nxyz*nelgt 
      call izero(iw,ntotg)
      do ie=1,nelv
         ieg=lglel(ie)
         iel=nxyz*(ieg-1)
         do i=1,nxyz
            iw(i+iel) = se2crs(i,1,ie)
         enddo
      enddo
c     call igop(iw,jw,'+  ',ntotg)
c     if (nid.eq.0) call out_se0(iw,nx,nelgt,name)
      call igop(iw,jw,'+  ',1)
      if (nid.eq.0) call out_se0(iw,nx,nelgt,name)
      call igop(iw,jw,'+  ',1)
      if (nid.eq.1) call out_se0(iw,nx,nelgt,name)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine out_se0(se2crs,nx,nel,name)
c
      include 'SIZE'
      integer se2crs(nx,nx,1)
      character*4 name
c
      write(6,*) 
      write(6,*) 'out_se',nx,name,nel
      do ie=nel-3,1,-4
         write(6,*)
         do j=nx,1,-1
            if(nx.eq.4) then
               write(6,4) name,((se2crs(i,j,k+ie),i=1,nx),k=0,3)
            elseif(nx.eq.3) then
               write(6,3) name,((se2crs(i,j,k+ie),i=1,nx),k=0,3)
            else
               write(6,2) name,((se2crs(i,j,k+ie),i=1,nx),k=0,3)
            endif
         enddo
      enddo
c
    4 format(a4,5x,4(4i5,3x))
    3 format(a4,5x,4(3i5,3x))
    2 format(a4,5x,4(2i5,3x))
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine crs_solve_h1(uf,vf)
c
c     Given an input vector v, this generates the H1 coarse-grid solution
c
      include 'SIZE'
      include 'DOMAIN'
      include 'INPUT'
      include 'GEOM'
      include 'SOLN'
      include 'PARALLEL'
      include 'CTIMER'

      real uf(1),vf(1)
      common /scrpre/ uc(lcr*lelt)
      common /scrpr2/ vc(lcr*lelt)
      common /scrxxt/ cmlt(lcr,lelv),mask(lcr,lelv)

      integer n_crs_tot
      save    n_crs_tot
      data    n_crs_tot /0/

      
      if (icalld.eq.0) then ! timer info
         ncrsl=0
         tcrsl=0.0
      endif
      ncrsl  = ncrsl  + 1

      ntot = nelv*nx1*ny1*nz1
      call col3(uf,vf,vmult,ntot)

      call map_f_to_c_h1_bilin(vc,uf)   ! additive Schwarz

#ifndef NOTIMER
      etime1=dnekclock()
#endif
      call crs_solve(xxth,uc,vc)
#ifndef NOTIMER
      tcrsl=tcrsl+dnekclock()-etime1
#endif

      call map_c_to_f_h1_bilin(uf,uc)


      return
      end
c-----------------------------------------------------------------------
c
      subroutine map_c_to_f_h1(uf,uc_in)
c
c     L2 Iterpolation operator:  H1-linear --> spectral GL mesh
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
      include 'SOLN'
c
      parameter (lxyz = lx1*ly1*lz1)
      real uc_in(1),uf(lxyz,lelt)
      common /screc/ w(lx1,lx1,2),v(lx1,2,ldim-1,lelt)
     $             , uc(2,2,ldim-1,lelt)
c
c
c     Map to coarse tensor product form
c
      do i=1,lcr*nelv
         j = se_to_lcrs(i,1)
         if (1.le.j.and.j.le.n_crs) then
            uc(i,1,1,1) = uc_in(j)
         else
            uc(i,1,1,1) = 0.
         endif
      enddo
      call map_c_to_f_h1_bilin(uf,uc)
c
c     ntot = nx1*ny1*nz1*nelv
c     call copy(pr,uf,ntot)
c     call prepost(.true.,'   ')
c     write(6,*) 'quit in map_c_to_f_h1'
c     call exitt
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_f_to_c_h1(uc_out,uf)
c
c     TRANSPOSE of H1 Iterpolation operator:                    T
c                                 (linear --> spectral GL mesh)
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
      include 'GEOM'
      real uc_out(1),uf(1)
c
      common /screc/ w(2,2,lx1),v(2,ly1,lz1,lelt)
     $             , uc(2,2,ldim-1,lelt)
c
c
      call map_f_to_c_h1_bilin(uc,uf)
c
c     Map from coarse tensor product form to reduced coarse form
c
      call rzero(uc_out,n_crs)
      do i=1,lcr*nelv
         j = se_to_lcrs(i,1)
         if (1.le.j.and.j.le.n_crs) then
            uc_out(j) = uc_out(j) + uc(i,1,1,1)
         endif
      enddo
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine set_h1_basis_bilin
c
      include 'SIZE'
      include 'DOMAIN'
      include 'WZ'
c
      do ix=1,nx1
         h1_basis(ix) = 0.5*(1.0-zgm1(ix,1))
         h1_basis(ix+nx1) = 0.5*(1.0+zgm1(ix,1))
      enddo
      call transpose(h1_basist,2,h1_basis,lx1)
c
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_c_to_f_h1_bilin(uf,uc)
c
c     H1 Iterpolation operator:  linear --> spectral GLL mesh
c
      include 'SIZE'
      include 'INPUT'
      include 'DOMAIN'
c
      parameter (lxyz = lx1*ly1*lz1)
      real uc(2,2,ldim-1,lelt),uf(lxyz,lelt)
      parameter (l2 = ldim-1)
      common /ctmp0/ w(lx1,lx1,2),v(lx1,2,l2,lelt)
c
      integer icalld
      save    icalld
      data    icalld/0/
      if (icalld.eq.0) then
         icalld=icalld+1
         call set_h1_basis_bilin
      endif
c
c
      n2 = 2
      if (if3d) then
c
         n31 = n2*n2*nelv
         n13 = nx1*nx1
c
         call mxm(h1_basis,nx1,uc,n2,v,n31)
         do ie=1,nelv
            do iz=1,n2
               call mxm(v(1,1,iz,ie),nx1,h1_basist,n2,w(1,1,iz),nx1)
            enddo
            call mxm(w,n13,h1_basist,n2,uf(1,ie),nx1)
         enddo
c
      else
c
         n31 = 2*nelv
         call mxm(h1_basis,nx1,uc,n2,v,n31)
         do ie=1,nelv
            call mxm(v(1,1,1,ie),nx1,h1_basist,n2,uf(1,ie),nx1)
         enddo
      endif
      return
      end
c
c-----------------------------------------------------------------------
c
      subroutine map_f_to_c_h1_bilin(uc,uf)
c
c     TRANSPOSE of H1 Iterpolation operator:                    T
c                                 (linear --> spectral GLL mesh)
c
      include 'SIZE'
      include 'DOMAIN'
      include 'INPUT'
c
      parameter (lxyz = lx1*ly1*lz1)
      real uc(lcr,lelt),uf(lx1,ly1,lz1,lelt)
      common /ctmp0/ w(2,2,lx1),v(2,ly1,lz1,lelt)
c
      integer icalld
      save    icalld
      data    icalld/0/
      if (icalld.eq.0) then
         icalld=icalld+1
         call set_h1_basis_bilin
      endif
c
      n2 = 2
      if (if3d) then
         n31 = ny1*nz1*nelv
         n13 = n2*n2
         call mxm(h1_basist,n2,uf,nx1,v,n31)
         do ie=1,nelv
            do iz=1,nz1
               call mxm(v(1,1,iz,ie),n2,h1_basis,nx1,w(1,1,iz),n2)
            enddo
            call mxm(w,n13,h1_basis,nx1,uc(1,ie),n2)
         enddo
      else
         n31 = ny1*nelv
         call mxm(h1_basist,n2,uf,nx1,v,n31)
         do ie=1,nelv
               call mxm(v(1,1,1,ie),n2,h1_basis,nx1,uc(1,ie),n2)
         enddo
      endif
 
      return
      end
c-----------------------------------------------------------------------
      subroutine get_local_crs_galerkin(a,ncl,nxc,h1,h2,w1,w2)

c     This routine generates Nelv submatrices of order ncl using
c     Galerkin projection

      include 'SIZE'

      real    a(ncl,ncl,1),h1(1),h2(1)
      real    w1(nx1*ny1*nz1,nelv),w2(nx1*ny1*nz1,nelv)

      parameter (lcrd=lx1**ldim)
      common /ctmp1z/ b(lcrd,8)

      integer e

      do j=1,ncl
         call gen_crs_basis(b(1,j),j) ! bi- or tri-linear interpolant
      enddo

      isd  = 1
      imsh = 1

      nxyz = nx1*ny1*nz1
      do j = 1,ncl
         do e = 1,nelv
            call copy(w1(1,e),b(1,j),nxyz)
         enddo

         call axhelm (w2,w1,h1,h2,imsh,isd)        ! A^e * bj

         do e = 1,nelv
         do i = 1,ncl
            a(i,j,e) = vlsc2(b(1,i),w2(1,e),nxyz)  ! bi^T * A^e * bj
         enddo
         enddo

      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_crs_basis(b,j) ! bi- tri-linear

      include 'SIZE'
      real b(nx1,ny1,nz1)

      real z0(lx1),z1(lx1)
      real zr(lx1),zs(lx1),zt(lx1)

      integer p,q,r

      call zwgll(zr,zs,nx1)

      do i=1,nx1
         z0(i) = .5*(1-zr(i))  ! 1-->0
         z1(i) = .5*(1+zr(i))  ! 0-->1
      enddo

      call copy(zr,z0,nx1)
      call copy(zs,z0,nx1)
      call copy(zt,z0,nx1)

      if (mod(j,2).eq.0)                        call copy(zr,z1,nx1)
      if (j.eq.3.or.j.eq.4.or.j.eq.7.or.j.eq.8) call copy(zs,z1,nx1)
      if (j.gt.4)                               call copy(zt,z1,nx1)

      if (ndim.eq.3) then
         do r=1,nx1
         do q=1,nx1
         do p=1,nx1
            b(p,q,r) = zr(p)*zs(q)*zt(r)
         enddo
         enddo
         enddo
      else
         do q=1,nx1
         do p=1,nx1
            b(p,q,1) = zr(p)*zs(q)
         enddo
         enddo
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine gen_crs_basis2(b,j) ! bi- tri-quadratic

      include 'SIZE'
      real b(nx1,ny1,nz1)

      real z0(lx1),z1(lx1),z2(lx1)
      real zr(lx1),zs(lx1),zt(lx1)

      integer p,q,r

      call zwgll(zr,zs,nx1)

      do i=1,nx1
         z0(i) = .5*(zr(i)-1)*zr(i)  ! 1-->0   ! Lagrangian, ordered
         z1(i) = 4.*(1+zr(i))*(1-zr(i))        ! lexicographically
         z2(i) = .5*(zr(i)+1)*zr(i)  ! 0-->1   !
      enddo

      call copy(zr,z0,nx1)
      call copy(zs,z0,nx1)
      call copy(zt,z0,nx1)

      if (mod(j,2).eq.0)                        call copy(zr,z1,nx1)
      if (j.eq.3.or.j.eq.4.or.j.eq.7.or.j.eq.8) call copy(zs,z1,nx1)
      if (j.gt.4)                               call copy(zt,z1,nx1)

      if (ndim.eq.3) then
         do r=1,nx1
         do q=1,nx1
         do p=1,nx1
            b(p,q,r) = zr(p)*zs(q)*zt(r)
         enddo
         enddo
         enddo
      else
         do q=1,nx1
         do p=1,nx1
            b(p,q,1) = zr(p)*zs(q)
         enddo
         enddo
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine get_vertex
      include 'SIZE'
      include 'TOTAL'
      include 'ZPER'

      common /ivrtx/ vertex ((2**ldim)*lelt)
      integer vertex

      integer icalld
      save    icalld
      data    icalld  /0/

      if (icalld.gt.0) return
      icalld = 1

      if (ifgtp) then
         call gen_gtp_vertex    (vertex, ncrnr)
      else
         call get_vert
      endif

      return
      end
c-----------------------------------------------------------------------

      subroutine split_gllnid(iunsort)

c  Split the sorted gllnid array (read from .map file) in NP contiguous
c  partitions. NP is an arbitrary number and denotes the numbers of CPUs
c  used to run NEK. 
c  To load balance the partitions in case of mod(nelgt,np)>0
c  add 1 contiguous entry (out of the sorted list) to every RANK_i where 
c  i = 1,mod(nelgt,np)+1
c
      include 'SIZE'
      include 'TOTAL'
 
      integer iunsort(lelg)

      if(nid.eq.0) then
        write(6,*) 'Number of processors not 2^k'
        write(6,*)  
     &   'split gllnid array into contiguous partitions'
      endif

      le    = nelgt/np
      nmod  = mod(nelgt,np)

      ! sort gllnid to do the paritioning
      call isort(gllnid,iunsort,nelgt)

      ip = -1
      do iel = 1,le
         ip = ip + 1
         gllnid(iel) = iel-1
      enddo
      iel0 = le
      
      do inode = 1,nmod
         do iel = 1,le
            ip = ip + 1
            ieln = (inode-1)*(le+1)
            gllnid(iel0+ieln+iel) = ip
         enddo
         gllnid(iel0+ieln+le+1) = ip
      enddo

      iel0 = iel0 + nmod*(le+1)
       
      do inode = nmod+1,np
         do iel = 1,le
            ip = ip + 1
            ieln = (inode-nmod-1)*le
            gllnid(iel0+ieln+iel) = ip
         enddo
      enddo

      ! unddo sorting
      call iswapt_ip(gllnid,iunsort,nelgt)

      return
      end
c-----------------------------------------------------------------------
      subroutine get_vert
      include 'SIZE'
      include 'TOTAL'
      include 'ZPER'

      common /ivrtx/ vertex ((2**ldim),lelt)
      integer vertex

      integer e,eg

      integer icalld
      save    icalld
      data    icalld  /0/
      if (icalld.gt.0) return
      icalld = 1

      ncrnr = 2**ndim

      if (ifmoab) then
#ifdef MOAB
c        call nekMOAB_loadConn (vertex, nelgt, ncrnr)
         write(6,*) 'need new moab loadconn interface cuz of vertex'
         call exitt
#else
         if(nid.eq.0) write(6,*)
     &     'ABORT: this version was not compiled with moab support!'
         call exitt
#endif
      else
         call get_vert_map(vertex, ncrnr, nelgt, '.map')
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine get_vert_map(vertex, nlv, nel, suffix)
      include 'SIZE'
      include 'INPUT'
      include 'PARALLEL'
      common /nekmpi/ nid_,np_,nekcomm,nekgroup,nekreal
      integer vertex(nlv,1)
      character*4 suffix

      parameter(mdw=2+2**ldim)
      parameter(ndw=7*lx1*ly1*lz1*lelv/mdw)
      common /scrns/ wk(mdw,ndw)   ! room for long ints, if desired
      integer wk,e,eg,eg0,eg1

      character*132 mapfle
      character*1   mapfle1(132)
      equivalence  (mapfle,mapfle1)

      if (nid.eq.0) then
         lfname = ltrunc(reafle,132) - 4
         call blank (mapfle,132)
         call chcopy(mapfle,reafle,lfname)
         call chcopy(mapfle1(lfname+1),suffix,4)
         open(unit=80,file=mapfle,status='old',err=999)
         read(80,*) neli,nnzi
         neli = iglmax(neli,1)   ! communicate to all procs
      else
         neli = 0
         neli = iglmax(neli,1)   ! communicate neli to all procs
      endif

      npass = 1 + (neli/ndw)
      if (npass.gt.np) then
         if (nid.eq.0) write(6,*) npass,np,neli,ndw,'Error get_vert_map'
         call exitt
      endif 

      len = 4*mdw*ndw
      if (nid.gt.0.and.nid.lt.npass) msg_id=irecv(nid,wk,len)
      call gsync

      if (nid.eq.0) then
         eg0 = 0
         do ipass=1,npass
            eg1 = min(eg0+ndw,neli)
            m   = 0
            do eg=eg0+1,eg1
               m = m+1
               read(80,*,end=998) (wk(k,m),k=2,mdw)
               gllnid(eg) = wk(2,m)  !proc map,  must still be divided
               wk(1,m)    = eg
            enddo
            if (ipass.lt.npass) call csend(ipass,wk,len,ipass,0) !send to ipass
            eg0 = eg1
         enddo
         ntuple = m
      elseif (nid.lt.npass) then
         call msgwait(msg_id)
         ntuple = ndw
      else
         ntuple = 0
      endif

c     Distribute and compute gllnid
      lng = 4*neli
      call bcast(gllnid,lng)

      log2p = log2(np)
      np2   = 2**log2p
      if (np2.ne.np) then
         call split_gllnid(gllel) ! no CPU=2^k restriction
      else
         npstar = ivlmax(gllnid,neli)+1
         nnpstr = npstar/np
         do eg=1,neli
            gllnid(eg) = gllnid(eg)/nnpstr
         enddo
      endif


      nelt=0 !     Count number of elements on this processor
      nelv=0
      do eg=1,neli
         if (gllnid(eg).eq.nid) then
            if (eg.le.nelgv) nelv=nelv+1
            if (eg.le.nelgt) nelt=nelt+1
         endif
      enddo

c     NOW: crystal route vertex by processor id

      do i=1,ntuple
         eg=wk(1,i)
         wk(2,i)=gllnid(eg)        ! processor id for element eg
      enddo

c     From fcrystal.c:
c        integer*? vi(mi,max)         ! these integer and real types
c        integer*? vl(ml,max)         !   better match up with what is
c        real      vr(mr,max)         !   in "types.h"
      vl=0
      ml=0
      vr=0
      mr=0
      key = 2  ! processor id is in wk(2,:)

      call crystal_transfer(cr_h,ntuple,ndw,wk,mdw,vl,ml,vr,mr,key)

      key = 1  ! Sort tuple list by eg := wk(1,:)
      call ftuple_list_sort(nelt,key,wk,mdw,vr,mr)

      iflag = 0
      if (ntuple.ne.nelt) then
         write(6,*) nid,ntuple,nelv,nelt,nelgt,' NELT FAIL'
         iflag=1
      else
         nv = 2**ndim
         do e=1,nelt
            call icopy(vertex(1,e),wk(3,e),nv)
         enddo
      endif

      iflag = iglmax(iflag,1)
      if (iflag.gt.0) then
         do mid=0,np-1
            call gsync
            if (mid.eq.nid)
     $      write(6,*) nid,ntuple,nelv,nelt,nelgt,' NELT FB'
            call gsync
         enddo
         call gsync
         call exitt
      endif

      if (nid.eq.0) write(6,*) 'done get_vert_map'
      return

  999 continue
      if (nid.eq.0) write(6,*) 'Could not find map file',mapfle
      call exitt

  998 continue
      if (nid.eq.0) write(6,*)ipass,npass,eg0,eg1,mdw,m,eg,'get vX fail'
      call exitt


      return
      end
c-----------------------------------------------------------------------
      subroutine irank_vecn(ind,nn,a,m,n,key,nkey,aa)
c
c     Compute rank of each unique entry a(1,i) 
c
c     Output:   ind(i)  i=1,...,n    (global) rank of entry a(*,i)
c               nn  = max(rank)
c               a(j,i) is permuted
c
c     Input:    a(j,i) j=1,...,m;  i=1,...,n  
c               m      :   leading dim. of v  (ldv must be .ge. m)
c               key    :   sort key
c               nkey   :   
c
c     Although not mandatory, this ranking procedure is probably
c     most effectively employed when the keys are pre-sorted. Thus,
c     the option is provided to sort vi() prior to the ranking.
c
c
      integer ind(n),a(m,n)
      integer key(nkey),aa(m)
      logical iftuple_ianeb,a_ne_b

      nk = min(nkey,m)
      call ituple_sort(a,m,n,key,nk,ind,aa)

c     Find unique a's
      call icopy(aa,a,m)
      nn     = 1
      ind(1) = nn
c
      do i=2,n
         a_ne_b = iftuple_ianeb(aa,a(1,i),key,nk)
         if (a_ne_b) then
            call icopy(aa,a(1,i),m)
            nn = nn+1
         endif
         ind(i) = nn ! set ind() to rank
      enddo

      return
      end
c-----------------------------------------------------------------------
      function igl_running_sum(in)
c
c     Global vector commutative operation using spanning tree.
c
c     Still need to fix for non-power-of-2 processor count
c

      include 'mpif.h'
      common /nekmpi/ nid,np,nekcomm,nekgroup,nekreal
      integer status(mpi_status_size)
      integer x,w,r


      x = in  ! running sum
      w = in  ! working buff
      r = 0   ! recv buff

      log2P = log2(np)
      mp    = 2**log2p
      lim   = log2P
      if (mp.ne.np) lim = log2P+1
      if (mp.ne.np) then  ! not yet fixed (3/23/09) pff
         write(6,*) nid,mp,np,'igl_running_sum fail, shoot pff'
         call exitt
      endif

      do l=1,lim
         mtype = l
         jid   = 2**(l-1)
         jid   = xor(nid,jid)   ! Butterfly, not recursive double

         call mpi_irecv (r,1,mpi_integer,mpi_any_source,mtype
     $                                            ,nekcomm,msg,ierr)
         call mpi_send  (w,1,mpi_integer,jid,mtype,nekcomm,ierr)
         call mpi_wait  (msg,status,ierr)
         w = w+r
         if (nid.gt.jid) x = x+r
c        write(6,1) l,nid,jid,r,w,x,'summer'
c   1    format(2i6,'nid',4i6,1x,a6)
      enddo

      igl_running_sum = x

      return
      end
c-----------------------------------------------------------------------
      subroutine gbtuple_rank(tuple,m,n,nmax,cr_h,nid,np,ind)

c     Return a unique rank for each matched tuple set. Global.  Balanced.
c
c     tuple is destroyed.
c
c     By "balanced" we mean that none of the tuple entries is likely to
c     be much more uniquely populated than any other, so that any of
c     the tuples can serve as an initial (parallel) sort key
c
c     First two slots in tuple(:,i) assumed empty

      integer ind(nmax),tuple(m,nmax),cr_h

      parameter (mmax=40)
      integer key(mmax),wtuple(mmax)

      if (m.gt.mmax) then
         write(6,*) nid,m,mmax,' gbtuple_rank fail'
         call exitt
      endif

      do i=1,n
         tuple(1,i) = mod(tuple(3,i),np) ! destination processor
         tuple(2,i) = i                  ! return location
      enddo

      ni= n
      vl=0
      ml=0
      vr=0
      mr=0
      ky=1  ! Assumes crystal_new already called
      call crystal_transfer(cr_h,ni,nmax,tuple,m,vl,ml,vr,mr,ky)

      nimx = iglmax(ni,1)
      if (ni.gt.nmax)   write(6,*) ni,nmax,n,'cr_xfer problem, A'
      if (nimx.gt.nmax) call exitt

      nkey = m-2
      do k=1,nkey
         key(k) = k+2
      enddo

      call irank_vecn(ind,nu,tuple,m,ni,key,nkey,wtuple)! tuple re-ordered,
                                                        ! but contents same

      nu_tot   = igl_running_sum(nu) ! running sum over P processors
      nu_prior = nu_tot - nu

      do i=1,ni
         tuple(3,i) = ind(i) + nu_prior  ! global ranking
      enddo

      call crystal_transfer(cr_h,ni,nmax,tuple,m,vl,ml,vr,mr,ky)

      nk = 1  ! restore to original order, local rank: 2; global: 3
      ky = 2
      call ituple_sort(tuple,m,n,ky,nk,ind,wtuple)


      return
      end
c-----------------------------------------------------------------------
      subroutine setvert3d(glo_num,ngv,nx,nel,vertex,ifcenter)

c     set up gsexch interfaces for direct stiffness summation.  
c     pff 2/3/98;  hmt revisited 12/10/01; pff (scalable) 3/22/09


      include 'SIZE'
      include 'CTIMER'
      include 'PARALLEL'
      include 'TOPOL'
      include 'GEOM'

      integer glo_num(1),vertex(0:1,0:1,0:1,1),ngv,nx
      logical ifcenter

      integer  edge(0:1,0:1,0:1,3,lelt),enum(12,lelt),fnum(6,lelt)
      common  /scrmg/ edge,enum,fnum
c     equivalence  (enum,fnum)

      integer etuple(4,2*12*lelt),ftuple(5,6,2*lelt)
      integer ind(2*12*lelt)
      common  /scrns/ ind,etuple
      equivalence  (etuple,ftuple)

      integer gvf(4),facet(4),aa(3),key(3),e,eg
      logical ifij
c
c     memory check...
c
      ny   = nx
      nz   = nx
      nxyz = nx*ny*nz
c
      if (nid.eq.0) write(6,*) '  setvert3d:',nx,ny,nz

c
      key(1)=1
      key(2)=2
      key(3)=3
c
c     Count number of unique vertices
      nlv  = 2**ndim
      ngv  = iglmax(vertex,nlv*nel)
c
c     Assign hypercube ordering of vertices.
      do e=1,nel
         do k=0,1
         do j=0,1
         do i=0,1
c           Local to global node number (vertex)
            il  = 1 + (nx-1)*i + nx*(nx-1)*j + nx*nx*(nx-1)*k
            ile = il + nx*ny*nz*(e-1)
            glo_num(ile)   = vertex(i,j,k,e)
         enddo
         enddo
         enddo
      enddo
      if (nx.eq.2) return
c
c     Assign edge labels by bounding vertices.  
      do e=1,nel
         do k=0,1
         do j=0,1
         do i=0,1
            edge(i,j,k,1,e) = vertex(i,j,k,e)  ! r-edge
            edge(j,i,k,2,e) = vertex(i,j,k,e)  ! s-edge
            edge(k,i,j,3,e) = vertex(i,j,k,e)  ! t-edge
         enddo
         enddo
         enddo
      enddo

c     Sort edges by bounding vertices.
      do i=0,12*nel-1
         if (edge(0,i,0,1,1).gt.edge(1,i,0,1,1)) then
            kswap = edge(0,i,0,1,1)
            edge(0,i,0,1,1) = edge(1,i,0,1,1)
            edge(1,i,0,1,1) = kswap
         endif
         etuple(3,i+1) = edge(0,i,0,1,1)
         etuple(4,i+1) = edge(1,i,0,1,1)
      enddo

c     Assign a number (rank) to each unique edge
      m    = 4
      n    = 12*nel
      nmax = 12*lelt*2  ! 2x for crystal router factor of safety
      call gbtuple_rank(etuple,m,n,nmax,cr_h,nid,np,ind)
      do i=1,12*nel
         enum(i,1) = etuple(3,i)
      enddo
      n_unique_edges = iglmax(enum,12*nel)

c
c= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
c     Assign global vertex numbers to SEM nodes on each edge
      n_on_edge = nx-2
      do e=1,nel

         iedg_loc = 0

c        Edges 1-4
         do k=0,1
         do j=0,1
            igv = ngv + n_on_edge*(enum(iedg_loc+1,e)-1)
            i0  = nx*(nx-1)*j + nx*nx*(nx-1)*k
            i0e = i0 + nxyz*(e-1)
            if (glo_num(i0e+1).lt.glo_num(i0e+nx)) then
               do i=2,nx-1                                   ! std forward case
                  glo_num(i0e+i) = igv + i-1
               enddo
            else
               do i=2,nx-1                                   ! backward case
                  glo_num(i0e+i) = igv + 1 + n_on_edge-(i-1)
               enddo
            endif
            iedg_loc = iedg_loc + 1
         enddo
         enddo
c
c        Edges 5-8
         do k=0,1
         do i=0,1
            igv = ngv + n_on_edge*(enum(iedg_loc+1,e)-1)
            i0  = 1+(nx-1)*i + nx*nx*(nx-1)*k
            i0e = i0 + nxyz*(e-1)
            if (glo_num(i0e).lt.glo_num(i0e+nx*(nx-1))) then
               do j=2,nx-1                                   ! std forward case
                  glo_num(i0e+(j-1)*nx) = igv + j-1
               enddo
            else
               do j=2,nx-1                                   ! backward case
                  glo_num(i0e+(j-1)*nx) = igv + 1 + n_on_edge-(j-1)
               enddo
            endif
            iedg_loc = iedg_loc + 1
         enddo
         enddo
c
c        Edges 9-12
         do j=0,1
         do i=0,1
            igv = ngv + n_on_edge*(enum(iedg_loc+1,e)-1)
            i0  = 1 + (nx-1)*i + nx*(nx-1)*j
            i0e = i0 + nxyz*(e-1)
            if (glo_num(i0e).lt.glo_num(i0e+nx*nx*(nx-1))) then
               do k=2,nx-1                                   ! std forward case
                  glo_num(i0e+(k-1)*nx*nx) = igv + k-1
               enddo
            else
               do k=2,nx-1                                   ! backward case
                  glo_num(i0e+(k-1)*nx*nx) = igv + 1 + n_on_edge-(k-1)
               enddo
            endif
            iedg_loc = iedg_loc + 1
         enddo
         enddo
      enddo
c
c     Currently assigned number of vertices
      ngvv  = ngv
      ngv   = ngv + n_unique_edges*n_on_edge
c
c
c     Assign faces by 3-tuples 
c
c     (The following variables all take the symmetric 
c     notation of IFACE as arguments:)
c
c     ICFACE(i,IFACE) -   Gives the 4 vertices which reside on face IFACE
c                         as depicted below, e.g. ICFACE(i,2)=2,4,6,8.
c
c                        3+-----+4    ^ Y
c                        /  2  /|     |
c     Edge 1 extends    /     / |     |
c       from vertex   7+-----+8 +2    +----> X
c       1 to 2.        |  4  | /     /
c                      |     |/     /
c                     5+-----+6    Z
c                         3
c
c
      nfaces=ndim*2
      ncrnr =2**(ndim-1)
      do e=1,nel
         do ifac=1,nfaces
            do icrn=1,ncrnr
               i                  = icface(icrn,ifac)-1
               facet(icrn)        = vertex(i,0,0,e)
            enddo
            call isort(facet,ind,ncrnr)
            call icopy(ftuple(3,ifac,e),facet,ncrnr-1)
         enddo
      enddo

c     Assign a number (rank) to each unique face
      m    = 5
      n    = 6*nel
      nmax = 6*lelt*2  ! 2x for crystal router factor of safety
      call gbtuple_rank(ftuple,m,n,nmax,cr_h,nid,np,ind)
      do i=1,6*nel
         fnum(i,1) = ftuple(3,i,1)
      enddo
      n_unique_faces = iglmax(fnum,6*nel)

c
c     Now assign global node numbers on the interior of each face
c
      call dsset (nx,ny,nz)
      do e=1,nel
       do iface=1,nfaces
         i0 = skpdat(1,iface)
         i1 = skpdat(2,iface)
         is = skpdat(3,iface)
         j0 = skpdat(4,iface)
         j1 = skpdat(5,iface)
         js = skpdat(6,iface)
c
c        On each face, count from minimum global vertex number,
c        towards smallest adjacent vertex number.  e.g., suppose
c        the face is defined by the following global vertex numbers:
c
c
c                    11+--------+81
c                      |c      d|
c                      |        |
c                      |        |
c                      |a      b|
c                    15+--------+62
c                          
c        We would count from c-->a, then towards d.
c
         gvf(1) = glo_num(i0+nx*(j0-1)+nxyz*(e-1))
         gvf(2) = glo_num(i1+nx*(j0-1)+nxyz*(e-1))
         gvf(3) = glo_num(i0+nx*(j1-1)+nxyz*(e-1))
         gvf(4) = glo_num(i1+nx*(j1-1)+nxyz*(e-1))
c
         call irank(gvf,ind,4)
c
c        ind(1) tells which element of gvf() is smallest.
c
         ifij = .false.
         if (ind(1).eq.1) then
            idir =  1
            jdir =  1
            if (gvf(2).lt.gvf(3)) ifij = .true.
         elseif (ind(1).eq.2) then
            idir = -1
            jdir =  1
            if (gvf(1).lt.gvf(4)) ifij = .true.
         elseif (ind(1).eq.3) then
            idir =  1
            jdir = -1
            if (gvf(4).lt.gvf(1)) ifij = .true.
         elseif (ind(1).eq.4) then
            idir = -1
            jdir = -1
            if (gvf(3).lt.gvf(2)) ifij = .true.
         endif
c
         if (idir.lt.0) then
            it=i0
            i0=i1
            i1=it
            is=-is
         endif
c
         if (jdir.lt.0) then
            jt=j0
            j0=j1
            j1=jt
            js=-js
         endif
c
         nxx = nx*nx
         n_on_face = (nx-2)*(ny-2)
         ig0 = ngv + n_on_face*(fnum(iface,e)-1)
         if (ifij) then
            k=0
            l=0
            do j=j0,j1,js
            do i=i0,i1,is
               k=k+1
c              this is a serious kludge to stay on the face interior
               if (k.gt.nx.and.k.lt.nxx-nx .and.
     $            mod(k,nx).ne.1.and.mod(k,nx).ne.0) then
c                 interior
                  l = l+1
                  glo_num(i+nx*(j-1)+nxyz*(e-1)) = l + ig0
               endif
            enddo
            enddo
         else
            k=0
            l=0
            do i=i0,i1,is
            do j=j0,j1,js
               k=k+1
c              this is a serious kludge to stay on the face interior
               if (k.gt.nx.and.k.lt.nxx-nx .and.
     $            mod(k,nx).ne.1.and.mod(k,nx).ne.0) then
c                 interior
                  l = l+1
                  glo_num(i+nx*(j-1)+nxyz*(e-1)) = l + ig0
               endif
            enddo
            enddo
         endif
       enddo
      enddo
c
c     Finally,  number interiors  
c     ngvs := number of global vertices on surface of subdomains
c
      ngve  = ngv
      ngv   = ngv + n_unique_faces*n_on_face
      ngvs  = ngv
c
      n_in_interior = (nx-2)*(ny-2)*(nz-2)
      if (ifcenter) then
         do e=1,nel
            ig0 = ngv + n_in_interior*(lglel(e)-1)
            l = 0
            do k=2,nz-1
            do j=2,ny-1
            do i=2,nx-1
               l = l+1
               glo_num(i+nx*(j-1)+nx*ny*(k-1)+nxyz*(e-1)) = ig0+l
            enddo
            enddo
            enddo
         enddo
      else
         do e=1,nel
            l = 0
            do k=2,nz-1
            do j=2,ny-1
            do i=2,nx-1
               l = l+1
               glo_num(i+nx*(j-1)+nx*ny*(k-1)+nxyz*(e-1)) = 0
            enddo
            enddo
            enddo
         enddo
      endif

      ngv = ngv + n_in_interior*melg
c
c     Quick check on maximum #dofs:
      m    = nxyz*nelt
      ngvm = iglmax(glo_num,m)
      if (nid.eq.0) write(6,1) nx,ngvv,ngve,ngvs,ngv,ngvm
    1 format('   setupds3d:',6i11)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine setvert2d(glo_num,ngv,nx,nel,vertex,ifcenter)

c     set up gsexch interfaces for direct stiffness summation.  
c     pff 2/3/98;  hmt revisited 12/10/01; pff (scalable) 3/22/09


      include 'SIZE'
      include 'CTIMER'
      include 'PARALLEL'
      include 'TOPOL'
      include 'GEOM'

      integer glo_num(1),vertex(0:1,0:1,1),ngv,nx
      logical ifcenter

      integer  edge(0:1,0:1,2,lelt),enum(4,lelt)
      common  /scrmg/ edge,enum

      integer etuple(4,4*lelt*2)
      integer ind(4*lelt*2)
      common  /scrns/ ind,etuple

      integer gvf(4),aa(3),key(3),e,eg
      logical ifij
c
c     memory check...
c
      ny   = nx
      nz   = 1
      nxyz = nx*ny*nz
c
      if (nid.eq.0) write(6,*) '  setvert2d:',nx,ny,nz

c
      key(1)=1
      key(2)=2
      key(3)=3
c
c     Count number of unique vertices
      nlv  = 2**ndim
      ngv  = iglmax(vertex,nlv*nel)
c
c     Assign hypercube ordering of vertices.
      do e=1,nel
         do j=0,1
         do i=0,1
c           Local to global node number (vertex)
            il  = 1 + (nx-1)*i + nx*(nx-1)*j
            ile = il + nx*ny*(e-1)
            glo_num(ile)   = vertex(i,j,e)
         enddo
         enddo
      enddo
      if (nx.eq.2) return
c
c     Assign edge labels by bounding vertices.  
      do e=1,nel
         do j=0,1
         do i=0,1
            edge(i,j,1,e) = vertex(i,j,e)  ! r-edge
            edge(j,i,2,e) = vertex(i,j,e)  ! s-edge
         enddo
         enddo
      enddo

c     Sort edges by bounding vertices.
      do i=0,4*nel-1
         if (edge(0,i,1,1).gt.edge(1,i,1,1)) then
            kswap = edge(0,i,1,1)
            edge(0,i,1,1) = edge(1,i,1,1)
            edge(1,i,1,1) = kswap
         endif
         etuple(3,i+1) = edge(0,i,1,1)
         etuple(4,i+1) = edge(1,i,1,1)
      enddo

c     Assign a number (rank) to each unique edge
      m    = 4
      n    = 4*nel
      nmax = 4*lelt*2  ! 2x for crystal router factor of safety

      call gbtuple_rank(etuple,m,n,nmax,cr_h,nid,np,ind)
      do i=1,4*nel
         enum(i,1) = etuple(3,i)
      enddo
      n_unique_edges = iglmax(enum,4*nel)

c
c= = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
c     Assign global vertex numbers to SEM nodes on each edge
      n_on_edge = nx-2
      do e=1,nel

         iedg_loc = 0

c        Edges 1-2
         do j=0,1
            igv = ngv + n_on_edge*(enum(iedg_loc+1,e)-1)
            i0  = nx*(nx-1)*j
            i0e = i0 + nxyz*(e-1)
            if (glo_num(i0e+1).lt.glo_num(i0e+nx)) then
               do i=2,nx-1                                   ! std forward case
                  glo_num(i0e+i) = igv + i-1
               enddo
            else
               do i=2,nx-1                                   ! backward case
                  glo_num(i0e+i) = igv + 1 + n_on_edge-(i-1)
               enddo
            endif
            iedg_loc = iedg_loc + 1
         enddo
c
c        Edges 3-4
         do i=0,1
            igv = ngv + n_on_edge*(enum(iedg_loc+1,e)-1)
            i0  = 1+(nx-1)*i
            i0e = i0 + nxyz*(e-1)
            if (glo_num(i0e).lt.glo_num(i0e+nx*(nx-1))) then
               do j=2,nx-1                                   ! std forward case
                  glo_num(i0e+(j-1)*nx) = igv + j-1
               enddo
            else
               do j=2,nx-1                                   ! backward case
                  glo_num(i0e+(j-1)*nx) = igv + 1 + n_on_edge-(j-1)
               enddo
            endif
            iedg_loc = iedg_loc + 1
         enddo
      enddo
c
c     Now assign global node numbers on the interior of each face
c
      nfaces=ndim*2
c
c     Finally,  number interiors  
c     ngvs := number of global vertices on surface of subdomains
c
      ngve  = ngv
      ngvs  = ngv
c
      n_in_interior = (nx-2)*(ny-2)
      if (ifcenter) then
         do e=1,nel
            ig0 = ngv + n_in_interior*(lglel(e)-1)
            l = 0
            do j=2,ny-1
            do i=2,nx-1
               l = l+1
               glo_num(i+nx*(j-1)+nxyz*(e-1)) = ig0+l
            enddo
            enddo
         enddo
      else
         do e=1,nel
            l = 0
            do j=2,ny-1
            do i=2,nx-1
               l = l+1
               glo_num(i+nx*(j-1)+nxyz*(e-1)) = 0
            enddo
            enddo
         enddo
      endif

      ngv = ngv + n_in_interior*melg
c
c     Quick check on maximum #dofs:
      m    = nxyz*nelt
      ngvm = iglmax(glo_num,m)
      if (nid.eq.0) write(6,1) nx,ngvv,ngve,ngvs,ngv,ngvm
    1 format('   setupds2d:',6i11)
c
      return
      end
c-----------------------------------------------------------------------
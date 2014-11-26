subroutine advection2(pretrans,ig,ix,iy,x,y)
  use timestepmod
  use gridmod
  use particlemod
  use inputparmod
  implicit none
  logical,intent(in) :: pretrans
  integer,intent(in) :: ig
  integer,intent(inout) :: ix,iy
  real*8,intent(inout) :: x,y
!-----------------------------------------------------------------------
! This routine computes the advection of IMC particles through the
! velocity grid in cylindrical geometry.
!-----------------------------------------------------------------------
!-- advection split parameter
  real*8,parameter :: alph2 = .5d0
  logical,parameter :: partstopper = .true.
!
  integer,external :: binsrch
  integer :: iyholder,ixholder
  real*8 :: rold,xold,yold,rx,ry
  real*8 :: help
  integer :: i,j
  integer :: imove,nmove
!-- statement functions
  integer :: l
  real*8 :: dx,dy,ymag
  dx(l) = grd_xarr(l+1) - grd_xarr(l)
  dy(l) = grd_yarr(l+1) - grd_yarr(l)
  ymag(l) = min(abs(grd_yarr(l)),abs(grd_yarr(l+1)))

!-- storing initial position
  xold = x
  yold = y
  rold = sqrt(x**2+y**2)
!-- setting tentative new position
  if(pretrans) then
     x = x*tsp_t/(tsp_t+alph2*tsp_dt)
     y = y*tsp_t/(tsp_t+alph2*tsp_dt)
  else
     x = x*(tsp_t+alph2*tsp_dt)/(tsp_t+tsp_dt)
     y = y*(tsp_t+alph2*tsp_dt)/(tsp_t+tsp_dt)
  endif

  if(x<grd_xarr(ix).or.abs(y)<ymag(iy)) then
!
!-- sanity check
     if(xold==0d0.and.yold==0d0) &
          stop 'advection2: invalid position update'
!-- finding tentative new index
     ixholder = binsrch(x,grd_xarr,grd_nx+1,0)
     iyholder = binsrch(y,grd_yarr,grd_ny+1,0)
!--correcting new index
!-- on y axis
     if(x==0d0) ixholder = ix
!-- on x axis
     if(y==0d0) iyholder = iy
!-- moved to negative y-line (unlikely)
     if(y<0d0.and.any(grd_yarr==y)) iyholder=iyholder-1

!-- checking if DDMC is active
     if(.not.in_puretran.and.partstopper) then
!-- initializing tracking cells
        i = ix
        j = iy
        help = 0d0
!-- number of cell moves
        nmove = ix-ixholder+abs(iy-iyholder)
        do imove=1,nmove

!-- speed at grid edges
           if(xold==0d0) then
              rx = 0d0
           else
              rx = rold*grd_xarr(i)/xold
           endif
           if(yold==0d0) then
              ry = 0d0
           else
              ry = rold*ymag(j)/abs(yold)
           endif

!-- using min displacement to move index
           help = max(rx,ry)

!-- x-edge
           if(help == rx) then
              if((grd_sig(i-1,j,1)+grd_cap(ig,i-1,j,1)) * &
                   min(dy(j),dx(i-1))*tsp_t >= prt_tauddmc) then
                 x = grd_xarr(i)
                 y = (yold/xold)*grd_xarr(i)
                 exit
              else
                 i = i-1
              endif

!-- y-edge
           else
              if(ymag(j)==abs(grd_yarr(j+1))) then
!-- y<0
                 if((grd_sig(i,j+1,1)+grd_cap(ig,i,j+1,1)) * &
                      min(dy(j+1),dx(i))*tsp_t >= &
                      prt_tauddmc) then
                    x = (xold/yold)*grd_yarr(j+1)
                    y = grd_yarr(j+1)
                    exit
                 else
                    j = j+1
                 endif
              else
!-- y>0
                 if((grd_sig(i,j-1,1)+grd_cap(ig,i,j-1,1)) * &
                      min(dy(j-1),dx(i))*tsp_t >= &
                      prt_tauddmc) then
                    x = (xold/yold)*grd_yarr(j)
                    y = grd_yarr(j)
                    exit
                 else
                    j = j-1
                 endif
              endif
           endif
        enddo
        ix = i
        iy = j

     else
!-- DDMC inactive, setting index to tentative value
        ix = ixholder
        iy = iyholder
     endif
  endif

end subroutine advection2

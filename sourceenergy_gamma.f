      subroutine sourceenergy_gamma
c     -----------------------------
      use mpimod
      use gridmod
      use totalsmod
!     use timestepmod
      implicit none
************************************************************************
* Add the energy deposition from gamma absorption to the energy source
* for optical particles.
************************************************************************
!     integer :: i
c
c-- dump whole profile (1D only)
!      do i=grd_nx,1,-1
!       write(6,*) 65-i,grd_emitex(i,1,1)/tsp_dt,grd_edep(i,1,1)/tsp_dt,
!     &   grd_edep(i,1,1)/grd_emitex(i,1,1)
!      enddo
c
c-- gamma deposition is energy source
      grd_emit = grd_emit + grd_edep
c
c-- save for output purposes
      grd_edepgam = grd_edep
c
c-- add gamma radiation source tot total
      if(impi==impi0) tot_eext = tot_eext + sum(grd_edep)
c
      end subroutine sourceenergy_gamma

      subroutine gasgrid_setup
c     ------------------------
      use inputstrmod
      use physconstmod
      use inputparmod
      use timestepmod
      use gasgridmod
      use manufacmod
      use miscmod, only:warn
      use profiledatamod
      implicit none
************************************************************************
* Initialize the gas grid, the part that is constant with time and
* temperature. The part that changes is done in gas_grid_update.
************************************************************************
      integer :: l,ll
      real*8 :: mass0fr(-2:gas_nelem,dd_ncell)
c
c-- agnostic mass setup
      dd_mass = str_massdd
c
c-- temperature
      if(in_srctype=='manu') then
       call init_manutemp
      elseif(in_consttemp==0d0) then
       call read_restart_file
      else
       dd_temp = in_consttemp
      endif
c
c
c-- used in fleck_factor
      dd_eraddens = pc_acoef*in_tempradinit**4
c
c
c-- temp and ur
      dd_ur = pc_acoef*dd_temp**4 !initial guess, may be overwritten by read_temp_str
c
c-- adopt partial masses from input file
      mass0fr = 0d0
      if(.not.in_noreadstruct) then
       if(.not.allocated(str_massfrdd)) stop 'input.str data not avail'
       if(in_igeom>1) stop 'gg_setup: str_massfr: no 2D'
       do l=1,str_nabund
        ll = str_iabund(l)
        if(ll>gas_nelem) ll = 0 !divert to container
        mass0fr(ll,:) = str_massfrdd(l,:)
       enddo
      elseif(.not.in_novolsrc) then
        mass0fr(28,:) = 1d0 !stable+unstable Ni abundance
        mass0fr(-1,:) = 1d0
      else
       stop 'gg_setup: no input.str and in_novolsrc=true!'
      endif
c
c-- convert mass fractions to # atoms
      call massfr2natomfr(mass0fr)
c
c-- output
C$$$      write(6,*) 'mass fractions'
C$$$      write(6,'(1p,33i12)') (l,l=-2,30)
C$$$      write(6,'(1p,33e12.4)') (mass0fr(:,l),l=1,dd_ncell)
C$$$      write(6,*) 'number fractions'
C$$$      write(6,'(1p,33i12)') (l,l=-2,30)
C$$$      write(6,'(1p,33e12.4)') dd_natom1fr(:,l,1,1),l=1,dd_ncell)
c
      end subroutine gasgrid_setup
c
c
c
      subroutine massfr2natomfr(mass0fr)
c     -------------------------
      use physconstmod
      use elemdatamod, only:elem_data
      use gasgridmod
      implicit none
      real*8,intent(inout) :: mass0fr(-2:gas_nelem,dd_ncell)
************************************************************************
* convert mass fractions to natom fractions, and mass to natom.
************************************************************************
      integer :: i,l
      real*8 :: help
c
      do i=1,dd_ncell
c!{{{
c-- sanity test
       if(all(mass0fr(1:,i)==0d0)) stop
     &    'massfr2natomfr: all mass fractions zero'
       if(any(mass0fr(1:,i)<0d0)) stop
     &    'massfr2natomfr: negative mass fractions'
c
c-- renormalize (the container fraction (unused elements) is taken out)
       mass0fr(:,i) = mass0fr(:,i)/sum(mass0fr(1:,i))
c
c-- partial mass
       dd_natom1fr(:,i)= mass0fr(:,i)*dd_mass(i)
c-- only stable nickel and cobalt
       dd_natom1fr(28,i) = dd_natom1fr(28,i) -
     &   dd_natom1fr(gas_ini56,i)
       dd_natom1fr(27,i) = dd_natom1fr(27,i) -
     &   dd_natom1fr(gas_ico56,i)
c
c-- convert to natoms
       do l=1,gas_nelem
        dd_natom1fr(l,i) = dd_natom1fr(l,i)/
     &    (elem_data(l)%m*pc_amu)
       enddo !j
c-- special care for ni56 and co56
!      help = elem_data(26)%m*pc_amu
       help = elem_data(28)%m*pc_amu !phoenix compatible
       dd_natom1fr(gas_ini56,i) =
     &   dd_natom1fr(gas_ini56,i)/help
       help = elem_data(27)%m*pc_amu !phoenix compatible
       dd_natom1fr(gas_ico56,i) =
     &   dd_natom1fr(gas_ico56,i)/help
c-- store initial fe/co/ni
       dd_natom0fr(-2:-1,i) = dd_natom1fr(-2:-1,i)!unstable
       dd_natom0fr(0:2,i) = dd_natom1fr(26:28,i)!stable
c-- add unstable to stable again
       dd_natom1fr(28,i) = dd_natom1fr(28,i) +
     &   dd_natom1fr(gas_ini56,i)
       dd_natom1fr(27,i) = dd_natom1fr(27,i) +
     &   dd_natom1fr(gas_ico56,i)
c
c-- total natom
       dd_natom(i) = sum(dd_natom1fr(1:,i))
c
c-- convert natoms to natom fractions
       dd_natom1fr(:,i) = dd_natom1fr(:,i)/
     &   dd_natom(i)
       dd_natom0fr(:,i) = dd_natom0fr(:,i)/
     &   dd_natom(i)
c!}}}
      enddo !i
c
      end subroutine massfr2natomfr

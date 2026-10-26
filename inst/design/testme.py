## reticulate::use_python("/usr/bin/python3"); reticulate::repl_python()
import array
import pytest
from osgeo import gdal
gdal.UseExceptions()
#pytestmark = pytest.mark.require_driver("netCDF")
from pathlib import Path

def test_gdalalg_mdim_mosaic_preserves_indexing_var_unit(tmp_path):
    UNIT = "days since 2000-01-01 00:00:00"
    def create_sources():
        with gdal.GetDriverByName("netCDF").CreateMultiDimensional(tmp_path / "test1.nc") as ds:
            rg = ds.GetRootGroup()
            z = rg.CreateDimension("z", "TEMPORAL", "", 1)
            z_ar = rg.CreateMDArray(
                "z", [z], gdal.ExtendedDataType.Create(gdal.GDT_Float64)
            )
            z_ar.SetUnit(UNIT)  # netCDF writes CF 'units'; reopens as GetUnit()
            z_ar.CreateAttribute(
                "long_name", [1], gdal.ExtendedDataType.CreateString()
            ).WriteString("time")
            z_ar.Write([10.0])
            ar = rg.CreateMDArray(
                "test", [z], gdal.ExtendedDataType.Create(gdal.GDT_UInt8)
            )
            ar.Write(array.array("B", [3]))
            
        with gdal.GetDriverByName("netCDF").CreateMultiDimensional(tmp_path / "test2.nc") as ds:
            rg = ds.GetRootGroup()
            z = rg.CreateDimension("z", "TEMPORAL", "", 1)
            z_ar = rg.CreateMDArray(
                "z", [z], gdal.ExtendedDataType.Create(gdal.GDT_Float64)
            )
            z_ar.SetUnit(UNIT)  # netCDF writes CF 'units'; reopens as GetUnit()
            z_ar.CreateAttribute(
                "long_name", [1], gdal.ExtendedDataType.CreateString()
            ).WriteString("time")
            z_ar.Write([20.0])
            ar = rg.CreateMDArray(
                "test", [z], gdal.ExtendedDataType.Create(gdal.GDT_UInt8)
            )
            ar.Write(array.array("B", [4]))
    
    create_sources()
    # reference: convert preserves the unit (passes today)
    with gdal.Run(
        "mdim", "convert",
        input=tmp_path / "test1.nc", output=tmp_path / "c.vrt", output_format="VRT",
    ) as alg:
        z = alg.Output().GetRootGroup().OpenMDArray("z")
        assert z.GetUnit() == UNIT

    # mosaic must preserve it too (fails before fix, passes after)
    with gdal.Run(
        "mdim", "mosaic",
        input=tmp_path / "test*.nc", output=tmp_path / "m.vrt",
        array="test", output_format="VRT",
    ) as alg:
        idx = alg.Output().GetRootGroup().OpenMDArray("test") \
                 .GetDimensions()[0].GetIndexingVariable()
        # did not work in gdal mdim mosaic
        assert idx.GetUnit() == UNIT
        # plain attributes survive:
        assert "long_name" in [a.GetName() for a in idx.GetAttributes()]

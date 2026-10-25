import asyncio
import io
import json
import logging
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from typing import Any, Optional

logger = logging.getLogger(__name__)

win32print = None
win32ui = None
win32con = None
pymupdf = None
Image = None
ImageWin = None

def _ensure_win32():
    global win32print, win32ui, win32con, pymupdf, Image, ImageWin
    if sys.platform != "win32":
        return
    for p in list(sys.path):
        if "site-packages" in p:
            w32 = os.path.join(p, "win32")
            pwin = os.path.join(p, "pythonwin")
            sys32 = os.path.join(p, "pywin32_system32")
            if os.path.isdir(w32) and w32 not in sys.path:
                sys.path.append(w32)
            if os.path.isdir(pwin) and pwin not in sys.path:
                sys.path.append(pwin)
            if os.path.isdir(sys32) and hasattr(os, "add_dll_directory"):
                try:
                    os.add_dll_directory(sys32)
                except Exception:
                    pass
    try:
        if win32print is None:
            import win32print
    except Exception as e:
        logger.debug(f"win32print load error: {e}")
    try:
        if win32ui is None:
            import win32ui
    except Exception as e:
        logger.debug(f"win32ui load error: {e}")
    try:
        if pymupdf is None:
            import pymupdf
    except Exception as e:
        try:
            import fitz as pymupdf
        except Exception:
            pass
    try:
        if Image is None:
            from PIL import Image, ImageWin
    except Exception:
        pass

_ensure_win32()


class PrintService:
    @staticmethod
    def get_printers() -> list[dict[str, Any]]:
        """
        Enumerate all installed and available printers on the office Windows PC.
        Returns a list of dicts with printer details.
        """
        _ensure_win32()
        printers: list[dict[str, Any]] = []
        default_printer_name: Optional[str] = None

        if win32print is not None and sys.platform == "win32":
            try:
                default_printer_name = win32print.GetDefaultPrinter()
            except Exception as e:
                logger.debug(f"Could not get default printer via win32print: {e}")

            try:
                # PRINTER_ENUM_LOCAL = 2, PRINTER_ENUM_CONNECTIONS = 4
                raw_list = win32print.EnumPrinters(
                    win32print.PRINTER_ENUM_LOCAL | win32print.PRINTER_ENUM_CONNECTIONS
                )
                for flags, desc, name, comment in raw_list:
                    printers.append({
                        "name": name,
                        "description": desc or name,
                        "comment": comment or "",
                        "is_default": (name == default_printer_name),
                        "status": "Ready",
                    })
            except Exception as e:
                logger.warning(f"Error enumerating printers via win32print: {e}")

        # If win32print returned nothing or failed, fallback to PowerShell
        if not printers and sys.platform == "win32":
            try:
                ps_cmd = (
                    "Get-CimInstance -ClassName Win32_Printer | "
                    "Select-Object Name, Default, PrinterStatus, PortName, DriverName | "
                    "ConvertTo-Json"
                )
                res = subprocess.run(
                    ["powershell", "-NoProfile", "-Command", ps_cmd],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if res.returncode == 0 and res.stdout.strip():
                    data = json.loads(res.stdout.strip())
                    if isinstance(data, dict):
                        data = [data]
                    for item in data:
                        printers.append({
                            "name": item.get("Name"),
                            "description": item.get("DriverName") or item.get("Name"),
                            "port": item.get("PortName") or "",
                            "is_default": bool(item.get("Default")),
                            "status": "Ready" if item.get("PrinterStatus") in (3, None) else "Busy",
                        })
            except Exception as e:
                logger.warning(f"PowerShell printer enumeration fallback failed: {e}")

        # Sort so default printer is first
        printers.sort(key=lambda p: (not p.get("is_default", False), p.get("name", "")))
        return printers

    @classmethod
    def get_default_printer_name(cls) -> Optional[str]:
        """
        Get the name of the default printer on the office PC.
        """
        _ensure_win32()
        if win32print is not None and sys.platform == "win32":
            try:
                return win32print.GetDefaultPrinter()
            except Exception:
                pass
        
        printers = cls.get_printers()
        for p in printers:
            if p.get("is_default"):
                return p.get("name")
        if printers:
            return printers[0].get("name")
        return None

    @classmethod
    def _print_pdf_gdi(cls, pdf_bytes: bytes, printer_name: str, job_name: str) -> int:
        """
        Renders PDF pages and spools them directly to the Windows printer DC using GDI.
        Returns the number of pages printed.
        """
        _ensure_win32()
        if pymupdf is None or win32ui is None:
            raise RuntimeError("PyMuPDF or win32ui is not available for GDI printing.")

        doc = pymupdf.open(stream=pdf_bytes, filetype="pdf")
        page_count = len(doc)
        if page_count == 0:
            raise ValueError("The provided PDF has no pages to print.")

        hDC = win32ui.CreateDC()
        hDC.CreatePrinterDC(printer_name)

        try:
            # Printable resolution
            HORZRES = 8
            VERTRES = 10
            printable_width = hDC.GetDeviceCaps(HORZRES)
            printable_height = hDC.GetDeviceCaps(VERTRES)

            hDC.StartDoc(job_name[:31])

            for page_idx in range(page_count):
                page = doc[page_idx]
                # Render at 300 DPI for high laser print clarity
                pix = page.get_pixmap(dpi=300)
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)

                # Maintain aspect ratio within printable boundary
                img_aspect = img.width / max(img.height, 1)
                target_aspect = printable_width / max(printable_height, 1)

                if img_aspect > target_aspect:
                    dest_w = printable_width
                    dest_h = int(printable_width / img_aspect)
                    dest_x = 0
                    dest_y = (printable_height - dest_h) // 2
                else:
                    dest_h = printable_height
                    dest_w = int(printable_height * img_aspect)
                    dest_x = (printable_width - dest_w) // 2
                    dest_y = 0

                hDC.StartPage()
                dib = ImageWin.Dib(img)
                dib.draw(hDC.GetHandleOutput(), (dest_x, dest_y, dest_x + dest_w, dest_y + dest_h))
                hDC.EndPage()

            hDC.EndDoc()
            return page_count
        finally:
            hDC.DeleteDC()
            doc.close()

    @classmethod
    def _print_pdf_edge_fallback(cls, pdf_bytes: bytes, printer_name: Optional[str] = None) -> None:
        """
        Fallback printer execution using headless Edge/Chrome if GDI fails.
        """
        edge_path = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
        if not os.path.exists(edge_path):
            edge_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
        
        if not os.path.exists(edge_path):
            raise RuntimeError("Neither GDI printing nor headless browser is available to spool PDF.")

        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp_file:
            tmp_path = tmp_file.name
            tmp_file.write(pdf_bytes)

        try:
            cmd = [edge_path, "--headless", "--disable-gpu"]
            if printer_name:
                cmd.append(f"--print-to-printer={printer_name}")
            else:
                cmd.append("--print-to-printer")
            cmd.append(tmp_path)

            res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            if res.returncode != 0:
                raise RuntimeError(f"Browser print failed with code {res.returncode}: {res.stderr}")
        finally:
            # Clean up after brief delay or try unlink
            try:
                os.remove(tmp_path)
            except Exception:
                pass

    @classmethod
    async def print_pdf(
        cls,
        pdf_bytes: bytes,
        printer_name: Optional[str] = None,
        job_name: str = "Godown Report",
        dry_run: bool = False,
        timeout: float = 25.0,
    ) -> dict[str, Any]:
        """
        Asynchronously sends a PDF document to the office PC's printer.
        If dry_run is True, verifies PDF parsing and printer DC creation without spooling physical paper.
        """
        target_printer = printer_name or cls.get_default_printer_name()
        if not target_printer:
            printers = cls.get_printers()
            if printers:
                target_printer = printers[0]["name"]
            else:
                raise RuntimeError("No printers found connected or configured on the Office PC.")

        def _do_print():
            _ensure_win32()
            if pymupdf is None:
                raise RuntimeError("PyMuPDF is not available to parse PDF.")
            doc = pymupdf.open(stream=pdf_bytes, filetype="pdf")
            page_count = len(doc)
            if page_count == 0:
                doc.close()
                raise ValueError("The provided PDF has no pages to print.")

            if dry_run:
                # Validate printer DC creation without spooling
                if win32ui is not None:
                    try:
                        hDC = win32ui.CreateDC()
                        hDC.CreatePrinterDC(target_printer)
                        hDC.DeleteDC()
                    except Exception as dc_err:
                        logger.warning(f"Dry-run DC test warning: {dc_err}")
                doc.close()
                return {
                    "success": True,
                    "printer": target_printer,
                    "pages": page_count,
                    "job_name": job_name,
                    "method": "dry_run_validation",
                    "timestamp": datetime.now().isoformat(),
                }

            doc.close()
            try:
                # 1. Native GDI high-precision print
                pages = cls._print_pdf_gdi(pdf_bytes, target_printer, job_name)
                return {
                    "success": True,
                    "printer": target_printer,
                    "pages": pages,
                    "job_name": job_name,
                    "method": "gdi",
                    "timestamp": datetime.now().isoformat(),
                }
            except Exception as gdi_err:
                logger.warning(f"GDI print failed for '{target_printer}': {gdi_err}. Attempting fallback...")
                try:
                    cls._print_pdf_edge_fallback(pdf_bytes, target_printer)
                    return {
                        "success": True,
                        "printer": target_printer,
                        "pages": page_count,
                        "job_name": job_name,
                        "method": "browser_spooler",
                        "timestamp": datetime.now().isoformat(),
                    }
                except Exception as fb_err:
                    raise RuntimeError(f"Print failed on Office PC. GDI error: {gdi_err}; Fallback error: {fb_err}")

        return await asyncio.wait_for(asyncio.to_thread(_do_print), timeout=timeout)

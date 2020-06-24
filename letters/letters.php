<?php
$letters = array();
$letters = array(
  "A" => "1",
  "B" => "4",
  "C" => "4",
  "D" => "2",
  "E" => "1",
  "F" => "4",
  "G" => "3",
  "H" => "4",
  "I" => "1",
  "J" => "10",
  "K" => "2",
  "L" => "1",
  "M" => "3",
  "N" => "1",
  "O" => "1",
  "P" => "4",
  "Q" => "10",
  "R" => "1",
  "S" => "1",
  "T" => "1",
  "U" => "2",
  "V" => "4",
  "W" => "4",
  "X" => "8",
  "Y" => "4",
  "Z" => "10",
);

$filename = './scrabble_blank.png';

header("Content-type: image/png");
$string               = $_GET['text'];
if (strlen($string) > 1) {
  $string = $string[0];
}
$im                   = imagecreatetruecolor(50, 50);
$src                  = imagecreatefrompng($filename);
list($width, $height) = getimagesize($filename);
imagecopyresized($im, $src, 0, 0, 0, 0, 50, 50, $width, $height);

$black  = imagecolorallocate($im, 0, 0, 0);
$px     = (imagesx($im) - 7.5 * strlen($string)) / 2;
$py     = (imagesy($im) - 15.5 ) / 2;
imagestring($im, 5, $px, $py, $string, $black);
$offset = (strlen($letters[$string])-1)*4;
imagestring($im, 1, 34-$offset, 32, $letters[$string], $black);
imagepng($im);
imagedestroy($im);

?>

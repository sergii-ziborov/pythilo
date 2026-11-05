'use client';
import {useEffect,useState} from 'react';
export function LabProgress({id}:{id:string}){
  const [passed,setPassed]=useState(false);
  useEffect(()=>{try{setPassed(localStorage.getItem(`pythilo:lab:${id}:v1:passed`)==='1');}catch{}},[id]);
  return passed?<em>✓ Completed</em>:null;
}
